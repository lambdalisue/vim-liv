-- liv.std.task — the editor-bound async runner (spec 0007).
--
-- It wires the editor's leaves (schedule/timer/wait, selected once at import)
-- into the pure liv.lua.async engine and re-exports the pure await/wrap, so a
-- plugin author gets a ready-to-use async API without injecting anything. The
-- module is honestly editor-bound (it is the thing that touches the loop), so
-- re-exporting the pure helpers here is not namespace-flattening.
local core = require("liv.core")
local async = require("liv.lua.async")

local leaves = (core.is_nvim and require("liv.std.task._nvim") or require("liv.std.task._vim"))(
  core
)

-- A running-task handle returned by run. Fields are filled in as the task
-- progresses; cancel stops it.
---@class liv.std.task.Handle
---@field done boolean Whether the task has finished.
---@field ok boolean Whether it finished successfully (valid once done).
---@field result any The result on success, or the error on failure (valid once done).
---@field cancel fun() Cancel the running task.

-- Type wiring for the language server. Several members are assigned from
-- references or wrap() calls, so they are typed here as class fields rather than
-- via tags on the assignments.
---@class liv.std.task
---@field await fun(task: fun(resume: fun(ok: boolean, ...: any))): ... Await a CPS task from within a running async function.
---@field wrap fun(f: fun(...: any)): fun(...: any): ... Wrap a callback-style function into an awaitable async function.
---@field schedule fun(fn: fun()) Schedule a function to run on the editor's main loop.
---@field run fun(afn: fun(), on_done?: fun(ok: boolean, result: any)): liv.std.task.Handle Run an async function; returns an observable handle.
---@field sleep fun(ms: integer) Inside an async function, suspend ~ms then resume.
---@field block fun(handle: liv.std.task.Handle, timeout?: integer): boolean, any Pump the loop until the task finishes; returns (ok, result).
local M = {}

-- Pure helpers from the engine (used inside an async function).
M.await = async.await
M.wrap = async.wrap

-- Schedule a function to run on the editor's main loop.
M.schedule = leaves.schedule

-- Run an async function. Returns a handle: { done, ok, result, cancel } so the
-- result can be observed (e.g. by block). on_done(ok, result|err) is optional.
function M.run(afn, on_done)
  local handle = { done = false }
  local inner = async.run(afn, {
    schedule = leaves.schedule,
    on_done = function(ok, result)
      handle.done, handle.ok, handle.result = true, ok, result
      if on_done then
        on_done(ok, result)
      end
    end,
  })
  handle.cancel = inner.cancel
  return handle
end

-- sleep(ms): inside an async function, suspend ~ms then resume.
M.sleep = async.wrap(function(ms, cb)
  return leaves.timer(ms, cb) -- returns a canceler
end)

-- block(handle[, timeout]): synchronously pump the editor loop until the task
-- finishes, then return (ok, result). This is a drive-to-completion helper for
-- scripts / CI / `:Liv*` commands that must finish before returning — NOT for
-- interactive use, where the editor already pumps the loop and blocking it would
-- freeze the UI. Returns whatever the task produced; `handle.done` stays false if
-- it timed out.
function M.block(handle, timeout)
  leaves.wait(timeout or 5000, function()
    return handle.done
  end)
  return handle.ok, handle.result
end

return M
