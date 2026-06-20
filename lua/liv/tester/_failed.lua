-- liv.tester._failed — persist the last run's failures and replay only them on
-- `--failed` (spec 0010).
--
-- After each run the failing tests' full titles (and their `file:line` origin,
-- captured at `it()` via debug.getinfo) are written to a state file under the
-- project's `.liv/`. `--failed` then restricts the next run to exactly those
-- names. The match is EXACT full-title set membership — NOT the Lua-pattern
-- `--select` path — because test names routinely contain magic characters
-- (`-`, `(`, `.`, `%`, `[`), which a pattern would mis-handle.
--
-- The state file is itself a Lua file returning a table (same rationale as the
-- config: no JSON parser, pure, runs under a bare interpreter). Pure Lua,
-- editor-independent, L1-testable.

local M = {}

-- The default state-file path under a project root.
---@param project string
---@return string
function M.state_path(project)
  return project .. "/.liv/last-run.lua"
end

-- Serialize a Lua string as a safe single-line literal (`%q` escapes quotes,
-- backslashes, and newlines). Used to write names verbatim into the state file.
local function quote(s)
  return string.format("%q", tostring(s))
end

-- Shell-quote a path for `os.execute` (single quotes, with embedded quotes
-- escaped). Used only for the `mkdir -p` of the state file's parent directory.
local function shquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Write the failures to `path` as a Lua file returning `{ failures = {...} }`.
-- Each entry keeps `name` and optional `file`/`line`. Creates the parent dir.
---@param path string
---@param failures { name: string, file?: string, line?: integer }[]
function M.save(path, failures)
  local dir = path:match("^(.*)/[^/]+$")
  if dir then
    os.execute("mkdir -p " .. shquote(dir))
  end
  local lines = { "return {", "  failures = {" }
  for _, f in ipairs(failures or {}) do
    local parts = { "name = " .. quote(f.name) }
    if f.file then
      parts[#parts + 1] = "file = " .. quote(f.file)
    end
    if f.line then
      parts[#parts + 1] = "line = " .. tostring(f.line)
    end
    lines[#lines + 1] = "    { " .. table.concat(parts, ", ") .. " },"
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  local fh = assert(io.open(path, "w"))
  fh:write(table.concat(lines, "\n"))
  fh:close()
end

-- Load the persisted failures from `path`; an absent or unreadable file yields an
-- empty list (so a first-ever `--failed` simply runs nothing extra). A malformed
-- file also degrades to empty rather than crashing the run.
---@param path string
---@return { name: string, file?: string, line?: integer }[]
function M.load(path)
  local chunk = loadfile(path)
  if not chunk then
    return {}
  end
  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" or type(result.failures) ~= "table" then
    return {}
  end
  return result.failures
end

-- Build a filter `fun(title, tags): boolean` that matches ONLY the exact full
-- titles in `names` (set membership), so replay is precise even for names full
-- of pattern-magic characters. An empty set matches nothing (there is nothing to
-- rerun).
---@param names string[]
---@return fun(title: string, tags: string[]): boolean
function M.filter(names)
  local set = {}
  for _, name in ipairs(names or {}) do
    set[name] = true
  end
  return function(title)
    return set[title] == true
  end
end

-- Extract the failing test names from a child's L3 per-test records. The child
-- now serializes its full event stream (each `{ "test_end", report }`), so the
-- parent collects failure names directly from the structured records rather than
-- re-parsing free text — exact names with pattern-magic characters survive intact.
---@param records table[] the cell's per-test event records
---@return string[]
function M.collect_l3_names(records)
  local names = {}
  for _, ev in ipairs(records or {}) do
    if ev[1] == "test_end" and ev[2] and ev[2].status == "failed" then
      names[#names + 1] = ev[2].name
    end
  end
  return names
end

return M
