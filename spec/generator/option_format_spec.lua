-- L1 unit test for liv.generator option emit (pure Lua). Turns parsed option
-- defs into a slim runtime metadata module (a boolean-name SET) + a LuaLS
-- annotation file for a named class (one class per availability namespace:
-- common / vim / nvim).
local format = require("liv.generator.option.format")

local function defs()
  return {
    { name = "shiftwidth", type = "number", scope = "buffer" },
    { name = "expandtab", type = "boolean", scope = "buffer" },
    { name = "filetype", type = "string", scope = "buffer" },
    { name = "wrap", type = "boolean", scope = "window" },
  }
end

describe("liv.generator.option.format", function()
  it("emits the runtime meta as a SET of ONLY boolean option names", function()
    local out = format(defs(), "liv.std.option.Common")
    local meta = assert(load(out.meta))()
    -- boolean options are present, valued plainly `true` (no {type,scope} record)
    assert.equal(true, meta.expandtab)
    assert.equal(true, meta.wrap)
    -- non-boolean options are ABSENT from the slim runtime set
    assert.is_nil(meta.shiftwidth)
    assert.is_nil(meta.filetype)
  end)

  it("emits no per-entry type/scope record in the runtime meta", function()
    local out = format(defs(), "liv.std.option.Common")
    -- the slim form carries no `type =`/`scope =` fields at all
    assert.is_nil(out.meta:find("type =", 1, true))
    assert.is_nil(out.meta:find("scope =", 1, true))
  end)

  it("keeps LuaLS @field annotations complete for ALL options, with mapped types", function()
    local out = format(defs(), "liv.std.option.Vim")
    assert.is_true(out.annotations:find("---@meta", 1, true) ~= nil)
    assert.is_true(out.annotations:find("---@class liv.std.option.Vim", 1, true) ~= nil)
    assert.is_true(out.annotations:find("---@field expandtab boolean", 1, true) ~= nil)
    assert.is_true(out.annotations:find("---@field shiftwidth integer", 1, true) ~= nil)
    assert.is_true(out.annotations:find("---@field filetype string", 1, true) ~= nil)
  end)

  it("sorts entries deterministically by name (stable output)", function()
    local a = format(defs(), "C").meta
    local b = format(defs(), "C").meta
    assert.equal(a, b)
    assert.is_true(a:find("expandtab", 1, true) < a:find("wrap", 1, true))
  end)
end)
