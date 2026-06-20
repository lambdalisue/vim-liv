-- liv.tester._init — the `liv-tester init` scaffold (spec 0010).
--
-- Writes a starter `.liv-tester.lua` config and an example `spec/` test into a
-- project, so a new liv plugin gets a working test setup in one command. It
-- REFUSES to clobber an existing `.liv-tester.lua` (the config is the file most
-- likely to hold real customization); a present example spec is left as-is.
-- Pure Lua + filesystem, editor-independent.

local M = {}

-- A starter config: every key documented inline so the file doubles as a
-- reference. Values are the built-in defaults, so an untouched scaffold behaves
-- exactly like no config at all.
local CONFIG_TEMPLATE = [[
-- .liv-tester.lua — liv-tester project configuration (a Lua file returning a
-- table). Precedence is CLI > this file > built-in default. Remove a key to take
-- the default. See spec 0010 (Testing) for the full reference.
return {
  -- reporter   = "spec",            -- spec | tap | jsonl | junit
  -- select     = { "tag:smoke" },   -- default selectors (multiple = OR)
  -- timeout    = 60,                -- per-file L3 timeout (seconds)
  -- jobs       = 1,                 -- parallel L3 child editors
  -- max_failures = 5,               -- stop launching L3 cells after N failures
  -- editor     = "both",            -- nvim | vim | both
  -- includes   = { "spec/*" },      -- only run files matching these globs
  -- excludes   = { "spec/wip/*" },  -- never run files matching these globs
}
]]

-- An example spec the author can run immediately and then replace.
local EXAMPLE_SPEC = [[
-- spec/example_spec.lua — a starter L1 test. Run it with `liv-tester` from the
-- project root. Replace it with your own specs under spec/ (L1, editor-free) and
-- test/ (L3, inside Vim +lua and Neovim).
describe("example", function()
  it("adds numbers", function()
    assert.equal(2, 1 + 1)
  end)
end)
]]

local function exists(path)
  local fh = io.open(path, "r")
  if fh then
    fh:close()
    return true
  end
  return false
end

local function shquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write_file(path, content)
  local fh, err = io.open(path, "w")
  if not fh then
    return false, err
  end
  fh:write(content)
  fh:close()
  return true
end

-- Scaffold the project at `project`. Returns `{ ok, message, created }`. It is a
-- no-op error (ok = false) when `.liv-tester.lua` already exists, so an
-- accidental re-run never overwrites a real config. The example spec is written
-- only when absent (an existing one is left untouched, reported in `created`).
---@param project string project root
---@return { ok: boolean, message: string, created: string[] }
function M.run(project)
  project = project or "."
  local config_path = project .. "/.liv-tester.lua"
  if exists(config_path) then
    return {
      ok = false,
      message = config_path .. " already exists; not overwriting",
      created = {},
    }
  end

  local created = {}
  local ok, err = write_file(config_path, CONFIG_TEMPLATE)
  if not ok then
    return {
      ok = false,
      message = "cannot write " .. config_path .. ": " .. tostring(err),
      created = {},
    }
  end
  created[#created + 1] = config_path

  os.execute("mkdir -p " .. shquote(project .. "/spec"))
  local spec_path = project .. "/spec/example_spec.lua"
  if not exists(spec_path) then
    local sok, serr = write_file(spec_path, EXAMPLE_SPEC)
    if not sok then
      return {
        ok = false,
        message = "cannot write " .. spec_path .. ": " .. tostring(serr),
        created = created,
      }
    end
    created[#created + 1] = spec_path
  end

  return { ok = true, message = "scaffolded liv-tester", created = created }
end

return M
