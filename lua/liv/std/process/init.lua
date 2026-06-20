-- liv.std.process — external process execution (spec 0006/0007). Editor-bound.
--
-- Three shapes (system/run share one spawn; cwd/env are spawn options on all):
--   * system(cmd, opts?) — one-shot: run to completion, return {code,stdout,stderr}.
--     Awaitable leaf built on the pure liv.lua.async engine, so it composes with
--     liv.std.task (run/await/block). Output is binary-safe raw bytes; cancelling
--     the running task kills the process (the awaitable returns a canceler).
--   * run(cmd, opts?) — synchronous one-shot: drives system to completion via
--     liv.std.task.block, so it needs NO async context (the "run a tool, get
--     output+exit" case). It pumps and blocks the loop, so it is for scripts /
--     CI / :Liv* commands, NOT the interactive UI path.
--   * open(cmd, opts) — streaming: a long-lived process whose stdout (and
--     optionally stderr) is delivered line by line, firing on_stdout once per
--     line many times over the process lifetime. Returns a handle to write()
--     stdin, close() stdin (EOF), and kill()/stop() the process. This is a plain
--     callback API (NOT an awaitable) because a streaming source has no single
--     result to await; on_exit is the single-shot completion signal.
-- Line mode is NUL-unsafe (a NUL byte corrupts the line split on both editors),
-- so open() is for line/text streams (e.g. JSONL); binary needs system().
local core = require("liv.core")
local async = require("liv.lua.async")
local task = require("liv.std.task")

local leaf = (core.is_nvim and require("liv.std.process._nvim") or require("liv.std.process._vim"))(
  core
)

-- The outcome of a finished process. stdout/stderr are raw, binary-safe bytes.
---@class liv.std.process.Result
---@field code integer Process exit code.
---@field stdout string Captured standard output (raw bytes).
---@field stderr string Captured standard error (raw bytes).

-- The outcome reported to open()'s on_exit when the process terminates.
---@class liv.std.process.exit
---@field code integer Process exit code.

-- Spawn options shared by system/run (and the spawn-shaped fields of open).
-- env EXTENDS the parent environment (the child keeps inherited variables plus
-- these); it does NOT replace it. Both behave identically across editors.
---@class liv.std.process.spawn_opts
---@field cwd? string Working directory to run the child in.
---@field env? table<string, string> Extra environment variables (extends the parent environment).

-- Callbacks for a streaming process. on_stdout fires once per stdout line, many
-- times over the process lifetime. on_stderr (optional) likewise per stderr
-- line. on_exit (optional) fires once when the process terminates. cwd/env are
-- the same spawn options as system/run.
---@class liv.std.process.open_opts : liv.std.process.spawn_opts
---@field on_stdout fun(line: string) Called once per line of standard output.
---@field on_stderr? fun(line: string) Called once per line of standard error.
---@field on_exit? fun(result: liv.std.process.exit) Called once when the process exits.

-- A handle to a running streaming process.
---@class liv.std.process.handle
---@field write fun(data: string) Write raw bytes to the process's stdin.
---@field close fun() Close the process's stdin (signal EOF); does not stop it.
---@field kill fun() Terminate the process.
---@field stop fun() Alias of kill — terminate the process.

---@class liv.std.process
local M = {}

-- The awaitable leaf: wrap always appends the callback as the LAST argument, so
-- (cmd, opts) must be normalized to a fixed arity before wrapping — otherwise a
-- bare system(cmd) call would place the callback where opts is expected.
local spawn = async.wrap(function(cmd, opts, cb)
  return leaf.spawn(cmd, opts, cb) -- returns a canceler
end)

-- system(cmd[, opts]): inside an async function, run `cmd` (a list, e.g.
-- {"git","status"}) to completion and return { code, stdout, stderr }. opts.cwd
-- sets the working directory; opts.env extends the environment. Awaitable;
-- cancelling the task kills the process.
---@param cmd string[]
---@param opts? liv.std.process.spawn_opts
---@return liv.std.process.Result
function M.system(cmd, opts)
  return spawn(cmd, opts or {})
end

-- run(cmd[, opts]): a SYNCHRONOUS one-shot — run `cmd` to completion and return
-- { code, stdout, stderr } WITHOUT requiring an async context. This is the 90%
-- case (run a tool, read its output and exit code) for scripts / CI / `:Liv*`
-- commands. Internally it drives system on a fresh task and blocks the editor
-- loop until it finishes via liv.std.task.block, so it MUST NOT be called on the
-- interactive UI path (it would freeze the loop while pumping). timeout defaults
-- to task.block's own default. On timeout the running child is cancelled (killed)
-- and the return is nil rather than a Result.
---@param cmd string[]
---@param opts? liv.std.process.spawn_opts
---@param timeout? integer Milliseconds to pump before giving up (default: task.block's default).
---@return liv.std.process.Result result The process result, or nil if it timed out.
function M.run(cmd, opts, timeout)
  local handle = task.run(function()
    return M.system(cmd, opts)
  end)
  local _, result = task.block(handle, timeout)
  if not handle.done then
    -- Timed out: kill the still-running child rather than orphan it.
    handle.cancel()
    return nil
  end
  return result
end

-- open(cmd, opts): spawn a long-lived process. opts.on_stdout fires once per
-- stdout line (many times); opts.on_stderr / opts.on_exit are optional. Returns
-- a handle with write(data), close() (EOF on stdin) and kill(). Plain callbacks,
-- not awaitable -- a streaming source has no single result to await.
---@param cmd string[]
---@param opts liv.std.process.open_opts
---@return liv.std.process.handle
function M.open(cmd, opts)
  return leaf.open(cmd, opts)
end

return M
