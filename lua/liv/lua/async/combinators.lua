-- Structured-concurrency combinators over the pure async engine (spec 0007).
--
-- These build ON await/wrap/run; they do not fork the engine. gather/select
-- spawn one child run per task onto the parent's `schedule` (inherited via
-- runner.current_schedule), so children interleave through the one main loop —
-- which is what makes bounded concurrency observable. channel/semaphore need no
-- schedule: they park a `resume` in a waiter list and wake it later, and the
-- parked resume already carries its own run's schedule from its `await`.
--
-- liv owns its own vocabulary (no Promise/then/all/race): gather (await-all),
-- select (first-to-finish), channel (async MPSC stream), semaphore (permits).

local runner = require("liv.lua.async.runner")

local M = {}

-- A unique sentinel returned by channel.recv after the channel is closed and
-- drained. Distinct from any sent value (including nil), so a consumer can loop
-- `while v ~= async.closed do ... end` unambiguously.
M.closed = setmetatable({}, {
  __tostring = function()
    return "liv.lua.async.closed"
  end,
})

-- gather(tasks): run zero-arg async functions concurrently and return a list of
-- their results in input order, after ALL complete. Fail-fast: on the first
-- task error, the rest are cancelled and that error propagates through await.
-- An empty list resolves to an empty list. Each task is a function called with
-- no arguments; its return value is one result slot (multiple returns collapse
-- to the first, matching `await`).
---@param tasks (fun(): any)[] Array of zero-arg async functions to run concurrently.
---@return any[] results The tasks' results, in input order.
function M.gather(tasks)
  local schedule = runner.current_schedule()
  if not schedule then
    error("gather must be called from within a running async function", 2)
  end
  local n = #tasks
  return runner.await(function(resume)
    if n == 0 then
      return resume(true, {})
    end
    local results = {}
    local remaining = n
    local handles = {}
    local done = false

    local function cancel_others(except)
      for i = 1, n do
        if i ~= except and handles[i] then
          pcall(handles[i].cancel)
        end
      end
    end

    for i = 1, n do
      handles[i] = runner.run(tasks[i], {
        schedule = schedule,
        on_done = function(ok, value)
          if done then
            return
          end
          if not ok then
            done = true
            cancel_others(i)
            return resume(false, value)
          end
          results[i] = value
          remaining = remaining - 1
          if remaining == 0 then
            done = true
            return resume(true, results)
          end
        end,
      })
    end
    -- Return a canceler so cancelling the PARENT run propagates to the children:
    -- the runner stores this as the await's `cancel_current` and invokes it on
    -- handle.cancel(). Without it, cancelling the parent would orphan the child
    -- runs (they would keep resuming on the shared schedule). `done` guards any
    -- in-flight child on_done from resuming after teardown.
    return function()
      done = true
      for i = 1, n do
        if handles[i] then
          pcall(handles[i].cancel)
        end
      end
    end
  end)
end

-- select(tasks): run async functions concurrently and return the INDEX and
-- RESULT of the FIRST to settle; the others are abandoned (cancelled). "Settle"
-- includes failure: if the first to finish errored, that error propagates
-- through await (consistent with await's contract). Requires at least one task.
---@param tasks (fun(): any)[] Array of zero-arg async functions to race.
---@return integer index The 1-based index of the first task to settle.
---@return any result That task's result.
function M.select(tasks)
  local schedule = runner.current_schedule()
  if not schedule then
    error("select must be called from within a running async function", 2)
  end
  local n = #tasks
  if n == 0 then
    error("select requires at least one task", 2)
  end
  return runner.await(function(resume)
    local handles = {}
    local done = false

    local function cancel_others(except)
      for i = 1, n do
        if i ~= except and handles[i] then
          pcall(handles[i].cancel)
        end
      end
    end

    for i = 1, n do
      handles[i] = runner.run(tasks[i], {
        schedule = schedule,
        on_done = function(ok, value)
          if done then
            return
          end
          done = true
          cancel_others(i)
          if not ok then
            return resume(false, value)
          end
          return resume(true, i, value)
        end,
      })
    end
    -- Like gather: return a canceler so cancelling the PARENT run tears down every
    -- child (not just the losers a settle cancels). Without it, a parent cancelled
    -- before any child settles would orphan all the child runs.
    return function()
      done = true
      for i = 1, n do
        if handles[i] then
          pcall(handles[i].cancel)
        end
      end
    end
  end)
end

-- channel(): an async MPSC channel. send(value) enqueues and never blocks;
-- recv() awaits the next value, parking the calling coroutine until one is
-- available. close() marks the channel closed: a recv that has drained the
-- buffer (now or later) returns the `async.closed` sentinel instead of parking.
-- Values are stored packed, so nil is a first-class queued value (distinct from
-- the closed sentinel).
---@class liv.lua.async.Channel
---@field send fun(value: any) Enqueue a value; never blocks.
---@field recv fun(): any Await and return the next value, or `async.closed` once closed and drained.
---@field close fun() Mark the channel closed; drained recvs return `async.closed`.

---@return liv.lua.async.Channel channel A new async MPSC channel.
function M.channel()
  -- buffer: head/tail/count, so a queued nil never corrupts length (# would).
  local buffer = {}
  local head, tail = 1, 1
  local waiters = {} -- parked recv resumes, FIFO
  local whead, wtail = 1, 1
  local is_closed = false

  local function buffer_count()
    return tail - head
  end

  local function push(value)
    buffer[tail] = value
    tail = tail + 1
  end

  local function shift()
    local value = buffer[head]
    buffer[head] = nil
    head = head + 1
    return value
  end

  local function waiter_count()
    return wtail - whead
  end

  local function park(resume)
    waiters[wtail] = resume
    wtail = wtail + 1
  end

  local function take_waiter()
    local resume = waiters[whead]
    waiters[whead] = nil
    whead = whead + 1
    return resume
  end

  local function send(value)
    if is_closed then
      error("send on a closed channel", 2)
    end
    if waiter_count() > 0 then
      -- Hand the value directly to the longest-waiting recv (FIFO fairness).
      take_waiter()(true, value)
    else
      push(value)
    end
  end

  local function close()
    if is_closed then
      return
    end
    is_closed = true
    -- Wake every parked recv with the closed sentinel; none can ever receive a
    -- value now (send is rejected after close).
    while waiter_count() > 0 do
      take_waiter()(true, M.closed)
    end
  end

  local function recv()
    return runner.await(function(resume)
      if buffer_count() > 0 then
        return resume(true, shift())
      end
      if is_closed then
        return resume(true, M.closed)
      end
      park(resume)
    end)
  end

  return { send = send, recv = recv, close = close }
end

-- semaphore(n): a counting semaphore with `n` permits. acquire() awaits until a
-- permit is free then takes one; release() returns a permit. With acquire/release
-- bracketing work and combined with gather, this bounds concurrency (e.g. permits
-- = 2 with 4 gathered tasks keeps at most 2 running at once). FIFO fairness:
-- release hands the freed permit directly to the longest-waiting acquirer rather
-- than incrementing and letting acquirers race.
---@class liv.lua.async.Semaphore
---@field acquire fun() Await until a permit is free, then take it.
---@field release fun() Return a permit (handed to the next waiter if any).

---@param n integer The number of permits (must be >= 0).
---@return liv.lua.async.Semaphore semaphore A new counting semaphore.
function M.semaphore(n)
  if type(n) ~= "number" or n < 0 or n % 1 ~= 0 then
    error("semaphore requires a non-negative integer permit count", 2)
  end
  local permits = n
  local waiters = {} -- parked acquire resumes, FIFO
  local whead, wtail = 1, 1

  local function acquire()
    return runner.await(function(resume)
      if permits > 0 then
        permits = permits - 1
        return resume(true)
      end
      waiters[wtail] = resume
      wtail = wtail + 1
    end)
  end

  local function release()
    if wtail > whead then
      -- Hand the permit directly to the head waiter (no permits bump): the
      -- waiter resumes holding the permit, preserving the invariant.
      local resume = waiters[whead]
      waiters[whead] = nil
      whead = whead + 1
      resume(true)
    else
      permits = permits + 1
    end
  end

  return { acquire = acquire, release = release }
end

return M
