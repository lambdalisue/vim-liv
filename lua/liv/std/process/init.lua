-- liv.std.process — external process execution (spec 0006/0007). Editor-bound.
--
-- Two shapes:
--   * system(cmd) — one-shot: run to completion, return {code,stdout,stderr}.
--     Awaitable leaf built on the pure liv.lua.async engine, so it composes with
--     liv.std.task (run/await/block). Output is binary-safe raw bytes; cancelling
--     the running task kills the process (the awaitable returns a canceler).
--   * open(cmd, opts) — streaming: a long-lived process whose stdout (and
--     optionally stderr) is delivered line by line, firing on_stdout once per
--     line many times over the process lifetime. Returns a handle to write()
--     stdin, close() stdin (EOF), and kill() the process. This is a plain
--     callback API (NOT an awaitable) because a streaming source has no single
--     result to await; on_exit is the single-shot completion signal.
-- Line mode is NUL-unsafe (a NUL byte corrupts the line split on both editors),
-- so open() is for line/text streams (e.g. JSONL); binary needs system().
local core = require("liv.core")
local async = require("liv.lua.async")

local leaf = (core.is_nvim and require("liv.std.process._nvim") or require("liv.std.process._vim"))(core)

-- The outcome of a finished process. stdout/stderr are raw, binary-safe bytes.
---@class liv.std.process.Result
---@field code integer Process exit code.
---@field stdout string Captured standard output (raw bytes).
---@field stderr string Captured standard error (raw bytes).

-- The outcome reported to open()'s on_exit when the process terminates.
---@class liv.std.process.exit
---@field code integer Process exit code.

-- Callbacks for a streaming process. on_stdout fires once per stdout line, many
-- times over the process lifetime. on_stderr (optional) likewise per stderr
-- line. on_exit (optional) fires once when the process terminates.
---@class liv.std.process.open_opts
---@field on_stdout fun(line: string) Called once per line of standard output.
---@field on_stderr? fun(line: string) Called once per line of standard error.
---@field on_exit? fun(result: liv.std.process.exit) Called once when the process exits.

-- A handle to a running streaming process.
---@class liv.std.process.handle
---@field write fun(data: string) Write raw bytes to the process's stdin.
---@field close fun() Close the process's stdin (signal EOF); does not stop it.
---@field kill fun() Terminate the process.

-- Type wiring for the language server. system is built from a wrap() call, so it
-- is typed here as a class field rather than via tags on the assignment.
---@class liv.std.process
---@field system fun(cmd: string[]): liv.std.process.Result Inside an async function, run `cmd` to completion and return its result.
---@field open fun(cmd: string[], opts: liv.std.process.open_opts): liv.std.process.handle Spawn a long-lived process, streaming stdout/stderr line by line.
local M = {}

-- system(cmd): inside an async function, run `cmd` (a list, e.g. {"git","status"})
-- to completion and return { code, stdout, stderr }. Awaitable; cancelling the
-- task kills the process.
M.system = async.wrap(function(cmd, cb)
  return leaf.spawn(cmd, cb) -- returns a canceler
end)

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
