-- liv.lua.async — editor-independent async engine (spec 0007).
--
-- The pure coroutine runner; `schedule` (and other leaves) are injected by the
-- caller. Library authors depend on this module to stay editor-independent.
-- Editor-bound `liv.std` modules (named by purpose, e.g. liv.std.process) wire a
-- real editor schedule/leaves into this engine rather than re-exporting it.
local runner = require("liv.lua.async.runner")
local combinators = require("liv.lua.async.combinators")

---@class liv.lua.async
---@field await fun(task: fun(resume: fun(ok: boolean, ...: any))): ... Await a CPS task from within a running async function.
---@field wrap fun(f: fun(...: any)): fun(...: any): ... Wrap a callback-style function into an awaitable async function.
---@field run fun(afn: fun(), opts: liv.lua.async.RunOpts): liv.lua.async.RunHandle Run an async function to completion.
---@field gather fun(tasks: (fun(): any)[]): any[] Run async functions concurrently; return their results in input order after all complete (fail-fast).
---@field select fun(tasks: (fun(): any)[]): integer, any Run async functions concurrently; return the index and result of the first to settle (others cancelled).
---@field channel fun(): liv.lua.async.Channel Create an async MPSC channel (send/recv/close).
---@field semaphore fun(n: integer): liv.lua.async.Semaphore Create a counting semaphore (acquire/release) to bound concurrency.
---@field closed table Sentinel returned by channel.recv once the channel is closed and drained.

---@type liv.lua.async
return {
  await = runner.await,
  wrap = runner.wrap,
  run = runner.run,
  gather = combinators.gather,
  select = combinators.select,
  channel = combinators.channel,
  semaphore = combinators.semaphore,
  closed = combinators.closed,
}
