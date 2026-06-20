-- liv.tester._watch — file-change detection for `--watch` (spec 0010).
--
-- `--watch` re-runs the suite whenever a source or spec file changes. Detection
-- is pure-Lua mtime POLLING (no inotify/libuv): a `snapshot` maps each watched
-- file to its mtime, and `changed` compares two snapshots. The polling LOOP is
-- best-effort and not unit-tested headless (it drives a real re-run); the pure
-- snapshot/diff functions are L1-testable.
--
-- mtimes come from `stat` via the shell — portable across macOS (BSD stat) and
-- Linux (GNU stat) by trying both formats — so `_watch` needs no editor and no
-- platform-specific binding.

local M = {}

-- The directories watched by default, relative to a project root: pure specs,
-- editor specs, and the source tree (a change in any re-runs the suite).
M.DIRS = { "spec", "test", "lua" }

-- Resolve `M.DIRS` to absolute paths under `project`.
---@param project string
---@return string[]
function M.dirs(project)
  local out = {}
  for _, d in ipairs(M.DIRS) do
    out[#out + 1] = project .. "/" .. d
  end
  return out
end

-- Stat a file's mtime (epoch seconds) via the shell, trying GNU then BSD `stat`.
-- Returns a number, or 0 when the file is unreadable.
local function mtime(path)
  local p =
    io.popen("stat -c %Y '" .. path .. "' 2>/dev/null || stat -f %m '" .. path .. "' 2>/dev/null")
  if not p then
    return 0
  end
  local line = p:read("*l")
  p:close()
  return tonumber(line) or 0
end

-- Build a snapshot mapping each `*.lua` file under the given directories to its
-- mtime. Missing directories simply contribute nothing.
---@param dirs string[]
---@return table<string, number>
function M.snapshot(dirs)
  local snap = {}
  for _, dir in ipairs(dirs) do
    local p = io.popen("find '" .. dir .. "' -name '*.lua' 2>/dev/null")
    if p then
      for path in p:lines() do
        snap[path] = mtime(path)
      end
      p:close()
    end
  end
  return snap
end

-- Did anything change between two snapshots? True when any file's mtime advanced,
-- a file appeared, or a file disappeared.
---@param before table<string, number>
---@param after table<string, number>
---@return boolean
function M.changed(before, after)
  for path, t in pairs(after) do
    if before[path] ~= t then
      return true
    end
  end
  for path in pairs(before) do
    if after[path] == nil then
      return true
    end
  end
  return false
end

-- Run `run_once` immediately, then poll for changes and re-run on each change,
-- forever (Ctrl-C to stop). `run_once` is injected so the loop is decoupled from
-- the CLI's run machinery. `opts.interval` is the poll interval in seconds
-- (default 1). Best-effort: it never returns under normal use.
---@param dirs string[]
---@param run_once fun()
---@param opts? { interval?: number, sleep?: fun(seconds: number) }
function M.loop(dirs, run_once, opts)
  opts = opts or {}
  local interval = opts.interval or 1
  local sleep = opts.sleep or function(seconds)
    os.execute("sleep " .. tostring(seconds))
  end
  local snap = M.snapshot(dirs)
  run_once()
  while true do
    sleep(interval)
    local now = M.snapshot(dirs)
    if M.changed(snap, now) then
      snap = now
      run_once()
    end
  end
end

return M
