-- liv.tester._async — drive a liv.lua.async async function to completion
-- SYNCHRONOUSLY, so a test asserts on the result the same turn it starts the
-- work instead of hand-rolling a queue+drain loop in every async spec.
--
-- It is a thin pump over the PURE async runner: a drainable fake `schedule`
-- collects resume thunks, the runner is started, then the queue is drained until
-- it empties. The run settles synchronously because every leaf used in a test
-- resumes synchronously (directly or via the queue) — there is no real event
-- loop. If the queue empties without the run settling (the async fn parked on a
-- task that never resumes), that is a test bug, surfaced as an error rather than
-- a silent hang.
--
-- `liv.lua.async.runner` is required LAZILY so loading `liv.tester` never pulls
-- the async machinery; it is a pure, editor-independent module, safe at L1.

local M = {}

-- Run `afn` (a liv.lua.async async function) to completion and return its value,
-- re-raising any error it (or an awaited task) produced. Raises if the run never
-- settles after the schedule drains.
---@param afn fun(): any The async function to drive.
---@return any result The value `afn` returned.
function M.drive(afn)
  local runner = require("liv.lua.async.runner")

  local queue = {}
  local function schedule(fn)
    queue[#queue + 1] = fn
  end

  local settled, ok, value = false, nil, nil
  runner.run(afn, {
    schedule = schedule,
    on_done = function(success, result)
      settled = true
      ok = success
      value = result
    end,
  })

  while queue[1] do
    table.remove(queue, 1)()
  end

  if not settled then
    error("async did not complete: the async function parked on a task that never resumed", 0)
  end
  if not ok then
    error(value, 0)
  end
  return value
end

return M
