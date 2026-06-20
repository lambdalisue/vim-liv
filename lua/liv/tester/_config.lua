-- liv.tester._config — the project config file (`.liv-tester.lua`) and the
-- precedence ladder CLI > config > default (spec 0010).
--
-- The config is a LUA FILE that RETURNS a table — not JSON. liv-tester runs under
-- a bare interpreter (luajit) where `liv.json` (editor-dependent) is unavailable,
-- and a Lua file needs no parser at all (`.busted` does the same). Keys mirror the
-- CLI: reporter, select, timeout, jobs, max_failures, editor, includes, excludes.
--
-- Discovery walks UP from a start directory to the filesystem root, returning the
-- nearest `.liv-tester.lua`; precedence is resolved per-key by `merge`, where a
-- CLI value is honored by PRESENCE (a key set to `false` still wins), then config,
-- then the built-in default. Pure Lua, editor-independent, L1-testable.

local M = {}

-- The discovered config file name, looked up by walking up the directory tree.
M.FILENAME = ".liv-tester.lua"

-- Load a config file: run it in a fresh environment and require a TABLE return.
-- A missing return, a non-table return, or a syntax/runtime error all raise so
-- the CLI can report a usage error rather than silently run with surprises.
---@param path string
---@return table config
function M.load(path)
  local chunk, err = loadfile(path)
  if not chunk then
    error("liv-tester: cannot load config " .. path .. ": " .. tostring(err), 0)
  end
  local ok, result = pcall(chunk)
  if not ok then
    error("liv-tester: error in config " .. path .. ": " .. tostring(result), 0)
  end
  if type(result) ~= "table" then
    error("liv-tester: config " .. path .. " must return a table, got " .. type(result), 0)
  end
  return result
end

-- Strip a trailing slash (but keep the root "/") so the parent walk is uniform.
local function strip_slash(dir)
  if #dir > 1 and dir:sub(-1) == "/" then
    return dir:sub(1, -2)
  end
  return dir
end

-- The parent directory of `dir`, or nil once at the filesystem root.
local function parent(dir)
  local up = dir:match("^(.*)/[^/]+$")
  if up == nil then
    return nil
  end
  if up == "" then
    return "/"
  end
  return up
end

local function exists(path)
  local fh = io.open(path, "r")
  if fh then
    fh:close()
    return true
  end
  return false
end

-- Walk up from `start_dir` looking for `FILENAME`; return the first match's path
-- or nil. The nearest config (closest ancestor) wins, mirroring `.busted` /
-- probitas walk-up discovery.
---@param start_dir string
---@return string? path
function M.discover(start_dir)
  local dir = strip_slash(start_dir or ".")
  while dir do
    local candidate = dir .. "/" .. M.FILENAME
    if exists(candidate) then
      return candidate
    end
    if dir == "/" then
      break
    end
    dir = parent(dir)
  end
  return nil
end

-- The set of keys the precedence ladder governs. Each is resolved independently:
-- CLI (by presence) > config > default.
M.KEYS = {
  "reporter",
  "select",
  "timeout",
  "jobs",
  "max_failures",
  "fail_fast",
  "editor",
  "includes",
  "excludes",
}

-- Resolve each governed key by precedence CLI > config > default. A key is taken
-- from `cli` when it is PRESENT there (non-nil — so an explicit `false` still
-- wins over config), else from `config` when present, else from `default`. `cli`
-- must therefore carry ONLY the keys the user actually supplied (absent = nil),
-- never post-defaulted values — otherwise `--jobs=1` could not be told from absent.
---@param cli table keys the user explicitly set on the command line (nil = absent)
---@param config table the loaded config table (may be empty)
---@param default table built-in defaults
---@return table merged
function M.merge(cli, config, default)
  cli = cli or {}
  config = config or {}
  default = default or {}
  local merged = {}
  for _, key in ipairs(M.KEYS) do
    if cli[key] ~= nil then
      merged[key] = cli[key]
    elseif config[key] ~= nil then
      merged[key] = config[key]
    else
      merged[key] = default[key]
    end
  end
  return merged
end

-- Translate a simple file glob into an anchored Lua pattern. Only `*` is magic
-- (one or more non-`/` characters, like a shell glob within a path segment); every
-- other character is escaped so `.`/`-`/`(`/etc. match literally. Intentionally
-- NOT full fnmatch (no `?`, no `[...]`, no `**`) — just enough to scope a run.
---@param glob string
---@return string pattern
local function glob_to_pattern(glob)
  local out = { "^" }
  for i = 1, #glob do
    local c = glob:sub(i, i)
    if c == "*" then
      out[#out + 1] = "[^/]*"
    else
      -- Escape any Lua-pattern magic character so it matches literally.
      out[#out + 1] = c:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
    end
  end
  out[#out + 1] = "$"
  return table.concat(out)
end

local function matches_any(path, globs)
  for _, glob in ipairs(globs) do
    if path:find(glob_to_pattern(glob)) then
      return true
    end
  end
  return false
end

-- Filter a discovered file list by `includes` (keep only files matching any
-- include glob; nil/empty = keep all) then `excludes` (drop any matching an
-- exclude glob). Excludes win over includes. Pure, order-preserving.
---@param files string[]
---@param includes string[]|nil
---@param excludes string[]|nil
---@return string[] kept
function M.filter_files(files, includes, excludes)
  local kept = {}
  for _, file in ipairs(files) do
    local keep = true
    if includes and #includes > 0 then
      keep = matches_any(file, includes)
    end
    if keep and excludes and #excludes > 0 and matches_any(file, excludes) then
      keep = false
    end
    if keep then
      kept[#kept + 1] = file
    end
  end
  return kept
end

return M
