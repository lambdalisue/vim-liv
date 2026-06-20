-- L1 unit test for the structured-concurrency combinators (spec 0007).
-- Drives coroutines synchronously with the same fake, drainable schedule the
-- runner spec uses — no editor. Concurrency is observable because every child
-- run resumes through the one shared queue.
local async = require("liv.lua.async")
local runner = require("liv.lua.async.runner")

-- A deterministic schedule: queue thunks, drain them on demand. Identical to the
-- runner spec's fake so the combinators are exercised on the real driving model.
local function make_schedule()
  local queue = {}
  local function schedule(fn)
    queue[#queue + 1] = fn
  end
  local function drain()
    while queue[1] do
      table.remove(queue, 1)()
    end
  end
  return schedule, drain
end

-- A task that resumes after `ticks` scheduler hops, yielding `value`. Each hop is
-- one await that re-schedules itself, so a higher `ticks` finishes later — this
-- lets a spec control completion order deterministically.
local function after(ticks, value)
  return function()
    for _ = 1, ticks do
      async.await(function(resume)
        resume(true)
      end)
    end
    return value
  end
end

describe("async.gather", function()
  it("collects results in input order after all complete", function()
    local schedule, drain = make_schedule()
    local got
    runner.run(function()
      -- Deliberately scramble completion order; results stay in input order.
      return async.gather({ after(3, "a"), after(1, "b"), after(2, "c") })
    end, {
      schedule = schedule,
      on_done = function(_, v)
        got = v
      end,
    })
    drain()
    assert.same({ "a", "b", "c" }, got)
  end)

  it("resolves an empty task list to an empty list", function()
    local schedule, drain = make_schedule()
    local got = "unset"
    runner.run(function()
      return async.gather({})
    end, {
      schedule = schedule,
      on_done = function(ok, v)
        got = { ok = ok, v = v }
      end,
    })
    drain()
    assert.is_true(got.ok)
    assert.same({}, got.v)
  end)

  it("runs the tasks concurrently, not sequentially", function()
    local schedule, drain = make_schedule()
    local running, peak = 0, 0
    local function tracked(ticks)
      return function()
        running = running + 1
        peak = math.max(peak, running)
        local r = after(ticks, ticks)()
        running = running - 1
        return r
      end
    end
    runner.run(function()
      return async.gather({ tracked(2), tracked(2), tracked(2) })
    end, { schedule = schedule })
    drain()
    -- If gather ran tasks sequentially, peak would be 1.
    assert.equal(3, peak)
  end)

  it("propagates the first task error and abandons the rest", function()
    local schedule, drain = make_schedule()
    local completed = {}
    local function boom()
      error("kaboom")
    end
    local function slow(value)
      return function()
        async.await(function(resume)
          resume(true)
        end)
        completed[#completed + 1] = value
        return value
      end
    end
    local got
    runner.run(function()
      return async.gather({ slow("x"), boom, slow("y") })
    end, {
      schedule = schedule,
      on_done = function(ok, err)
        got = { ok = ok, err = err }
      end,
    })
    drain()
    assert.is_false(got.ok)
    assert.is_true(tostring(got.err):find("kaboom", 1, true) ~= nil)
    -- The siblings were cancelled before their second tick completed.
    assert.same({}, completed)
  end)

  it("is awaitable and composable with surrounding async code", function()
    local schedule, drain = make_schedule()
    local got
    runner.run(function()
      local results = async.gather({ after(1, 10), after(1, 20) })
      return results[1] + results[2]
    end, {
      schedule = schedule,
      on_done = function(_, v)
        got = v
      end,
    })
    drain()
    assert.equal(30, got)
  end)

  it("cancelling the parent run propagates to the gathered children", function()
    -- Each child ticks a shared counter on every hop. After the parent is
    -- cancelled, NO child may advance the counter — the children must be torn
    -- down, not left resuming on the shared schedule.
    local queue = {}
    local function schedule(fn)
      queue[#queue + 1] = fn
    end
    local function step(k)
      for _ = 1, k do
        if not queue[1] then
          break
        end
        table.remove(queue, 1)()
      end
    end
    local ticks = 0
    local function ticker()
      return function()
        for _ = 1, 50 do
          async.await(function(resume)
            resume(true)
          end)
          ticks = ticks + 1
        end
      end
    end
    local handle = runner.run(function()
      return async.gather({ ticker(), ticker() })
    end, { schedule = schedule })
    step(8) -- let the children start and tick a few times
    local before = ticks
    assert.is_true(before > 0) -- sanity: the children actually ran
    handle.cancel()
    step(1000) -- drain everything still queued
    assert.equal(before, ticks) -- frozen: no child ticked after cancel
  end)
end)

describe("async.select", function()
  it("returns the index and result of the first task to finish", function()
    local schedule, drain = make_schedule()
    local got
    runner.run(function()
      local index, value = async.select({ after(3, "slow"), after(1, "fast"), after(2, "mid") })
      return { index, value }
    end, {
      schedule = schedule,
      on_done = function(_, v)
        got = v
      end,
    })
    drain()
    assert.same({ 2, "fast" }, got)
  end)

  it("abandons the losing tasks", function()
    local schedule, drain = make_schedule()
    local completed = {}
    local function tracked(ticks, value)
      return function()
        local r = after(ticks, value)()
        completed[#completed + 1] = value
        return r
      end
    end
    runner.run(function()
      return async.select({ tracked(1, "win"), tracked(5, "lose") })
    end, { schedule = schedule })
    drain()
    -- Only the winner finished; the loser was cancelled mid-flight.
    assert.same({ "win" }, completed)
  end)

  it("propagates the error when the first to settle errored", function()
    local schedule, drain = make_schedule()
    local got
    runner.run(function()
      return async.select({
        function()
          error("first-fail")
        end,
        after(5, "late"),
      })
    end, {
      schedule = schedule,
      on_done = function(ok, err)
        got = { ok = ok, err = err }
      end,
    })
    drain()
    assert.is_false(got.ok)
    assert.is_true(tostring(got.err):find("first-fail", 1, true) ~= nil)
  end)

  it("cancelling the parent before any task settles tears down all children", function()
    -- The children need 50 hops to settle; cancel the parent long before then and
    -- assert no child keeps ticking afterward.
    local queue = {}
    local function schedule(fn)
      queue[#queue + 1] = fn
    end
    local function step(k)
      for _ = 1, k do
        if not queue[1] then
          break
        end
        table.remove(queue, 1)()
      end
    end
    local ticks = 0
    local function ticker()
      return function()
        for _ = 1, 50 do
          async.await(function(resume)
            resume(true)
          end)
          ticks = ticks + 1
        end
      end
    end
    local handle = runner.run(function()
      return async.select({ ticker(), ticker() })
    end, { schedule = schedule })
    step(6) -- a few hops, far short of either child settling
    local before = ticks
    assert.is_true(before > 0)
    handle.cancel()
    step(1000)
    assert.equal(before, ticks)
  end)
end)

describe("async.channel", function()
  it("delivers a value buffered before recv", function()
    local schedule, drain = make_schedule()
    local got
    runner.run(function()
      local ch = async.channel()
      ch.send("hello")
      return ch.recv()
    end, {
      schedule = schedule,
      on_done = function(_, v)
        got = v
      end,
    })
    drain()
    assert.equal("hello", got)
  end)

  it("preserves FIFO order across multiple sends", function()
    local schedule, drain = make_schedule()
    local got
    runner.run(function()
      local ch = async.channel()
      ch.send(1)
      ch.send(2)
      ch.send(3)
      return { ch.recv(), ch.recv(), ch.recv() }
    end, {
      schedule = schedule,
      on_done = function(_, v)
        got = v
      end,
    })
    drain()
    assert.same({ 1, 2, 3 }, got)
  end)

  it("blocks recv until a later send delivers (single consumer, two producers)", function()
    local schedule, drain = make_schedule()
    local received = {}
    local ch
    runner.run(function()
      ch = async.channel()
      -- Consumer parks on an empty channel, then drains both producers' values.
      for _ = 1, 2 do
        received[#received + 1] = ch.recv()
      end
    end, { schedule = schedule })
    drain() -- consumer now parked, channel empty

    -- Two independent producer runs send into the same channel.
    runner.run(function()
      ch.send("p1")
    end, { schedule = schedule })
    runner.run(function()
      ch.send("p2")
    end, { schedule = schedule })
    drain()

    assert.same({ "p1", "p2" }, received)
  end)

  it("treats nil as a first-class queued value", function()
    local schedule, drain = make_schedule()
    local got
    runner.run(function()
      local ch = async.channel()
      ch.send(nil)
      ch.send("after-nil")
      local first = ch.recv()
      local second = ch.recv()
      return { is_nil = first == nil, second = second }
    end, {
      schedule = schedule,
      on_done = function(_, v)
        got = v
      end,
    })
    drain()
    assert.is_true(got.is_nil)
    assert.equal("after-nil", got.second)
  end)

  it("returns the closed sentinel for a recv after close and drain", function()
    local schedule, drain = make_schedule()
    local got
    runner.run(function()
      local ch = async.channel()
      ch.send("last")
      ch.close()
      local drained = ch.recv() -- still gets the buffered value
      local after_close = ch.recv() -- now sees the sentinel
      return { drained = drained, sentinel = after_close == async.closed }
    end, {
      schedule = schedule,
      on_done = function(_, v)
        got = v
      end,
    })
    drain()
    assert.equal("last", got.drained)
    assert.is_true(got.sentinel)
  end)

  it("wakes a parked recv with the sentinel when the channel is closed", function()
    local schedule, drain = make_schedule()
    local got
    local ch
    runner.run(function()
      ch = async.channel()
      got = ch.recv() == async.closed
    end, { schedule = schedule })
    drain() -- recv parked on empty channel
    ch.close()
    drain()
    assert.is_true(got)
  end)
end)

describe("async.semaphore", function()
  it("bounds concurrency to the permit count", function()
    local schedule, drain = make_schedule()
    local sem = async.semaphore(2)
    local running, peak = 0, 0
    local function worker(ticks)
      return function()
        sem.acquire()
        running = running + 1
        peak = math.max(peak, running)
        after(ticks, true)()
        running = running - 1
        sem.release()
      end
    end
    runner.run(function()
      return async.gather({ worker(2), worker(2), worker(2), worker(2) })
    end, { schedule = schedule })
    drain()
    -- Four tasks, two permits: never more than two run concurrently.
    assert.equal(2, peak)
  end)

  it("hands a released permit to the longest-waiting acquirer (FIFO)", function()
    local schedule, drain = make_schedule()
    local order = {}
    local sem = async.semaphore(1)
    local function worker(label)
      return function()
        sem.acquire()
        order[#order + 1] = label
        after(1, true)()
        sem.release()
      end
    end
    runner.run(function()
      return async.gather({ worker("a"), worker("b"), worker("c") })
    end, { schedule = schedule })
    drain()
    assert.same({ "a", "b", "c" }, order)
  end)

  it("admits up to n acquirers immediately", function()
    local schedule, drain = make_schedule()
    local sem = async.semaphore(2)
    local entered = 0
    local function enter()
      return function()
        sem.acquire()
        entered = entered + 1
        -- Hold the permit forever: park without ever resuming or releasing,
        -- so the permit is never returned to the pool.
        async.await(function() end)
      end
    end
    runner.run(function()
      return async.gather({ enter(), enter(), enter() })
    end, { schedule = schedule })
    drain()
    -- Two permits held indefinitely, so exactly two acquirers entered; the
    -- third stays parked on acquire (gather never settles — fine here).
    assert.equal(2, entered)
  end)
end)
