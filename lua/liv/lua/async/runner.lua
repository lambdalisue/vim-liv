-- Editor-agnostic coroutine runner (spec 0007).
--
-- This is the bulk of the async machinery and is pure Lua: an async function
-- runs inside a coroutine and calls await(task); editor-specific scheduling and
-- leaf primitives are injected, so the runner is driven synchronously with fakes
-- in L1 tests. `schedule` is supplied per run (the real backend wires it; tests
-- pass a drainable fake), keeping this module free of any editor dependency.

local compat = require("liv.lua.compat")
local pack, unpack = compat.pack, compat.unpack

local M = {}

-- await: yield a CPS task; the resume delivers (ok, ...). On failure the error
-- propagates as a Lua error, so pcall/cleanup/rethrow behave as in sync code.
---Await a CPS task from within a running async function.
---@param task fun(resume: fun(ok: boolean, ...: any)) Receives a resume callback; call it with `(true, ...)` on success or `(false, err)` on failure. May return a canceler.
---@return any ... The values passed to `resume` after the leading `ok`.
function M.await(task)
  local res = pack(coroutine.yield(task))
  if not res[1] then
    error(res[2], 0)
  end
  return unpack(res, 2, res.n)
end

-- wrap f(args..., cb) (cb called as cb(result...)) into an async function that
-- is awaitable via await().
---Wrap a callback-style function into an awaitable async function.
---@param f fun(...: any) A function whose last argument is a callback invoked as `cb(result...)`; may return a canceler.
---@return fun(...: any): ... awaitable An async function that, when called, awaits `f` and returns its callback results.
function M.wrap(f)
  return function(...)
    local args = pack(...)
    return M.await(function(resume)
      args[args.n + 1] = function(...)
        resume(true, ...)
      end
      args.n = args.n + 1
      return f(unpack(args, 1, args.n)) -- may return a canceler
    end)
  end
end

-- Run an async function to completion.
--   opts.schedule  (required) resume thunks on the main loop.
--   opts.on_done   (optional) called once as on_done(ok, result|err).
-- Returns a handle with :cancel().
---@class liv.lua.async.RunOpts
---@field schedule fun(fn: fun()) Required. Schedules a thunk to resume on the main loop.
---@field on_done? fun(ok: boolean, result: any) Optional. Called once with the result on success or the error on failure/cancellation.

---@class liv.lua.async.RunHandle
---@field cancel fun() Cancels the run; settles `on_done` with `(false, "cancelled")` if still pending.

---Run an async function to completion.
---@param afn fun() The async function to run; may call `await` while running.
---@param opts liv.lua.async.RunOpts Run options (`schedule` required, `on_done` optional).
---@return liv.lua.async.RunHandle handle A handle exposing `cancel`.
function M.run(afn, opts)
  opts = opts or {}
  local schedule = opts.schedule
  local on_done = opts.on_done
  if type(schedule) ~= "function" then
    error("runner.run requires opts.schedule to be a function", 2)
  end

  local co = coroutine.create(afn)
  -- `settled` guards the single terminal transition: once the run finishes,
  -- fails, or is cancelled, no further on_done / canceler may fire.
  local settled, cancel_current = false, nil

  local function finish(ok, value)
    if settled then
      return
    end
    settled = true
    if on_done then
      on_done(ok, value)
    end
  end

  local function step(...)
    if settled then
      return
    end
    local ok, task = coroutine.resume(co, ...)
    if not ok then
      return finish(false, task)
    end
    if coroutine.status(co) == "dead" then
      return finish(true, task)
    end
    local resumed = false
    cancel_current = task(function(...)
      if resumed or settled then
        return
      end
      resumed = true
      local a = pack(...)
      schedule(function()
        step(unpack(a, 1, a.n))
      end) -- always resume on the main loop
    end)
  end

  schedule(function()
    step()
  end)

  return {
    cancel = function()
      if settled then
        return
      end
      if type(cancel_current) == "function" then
        pcall(cancel_current)
      end
      finish(false, "cancelled")
    end,
  }
end

return M
