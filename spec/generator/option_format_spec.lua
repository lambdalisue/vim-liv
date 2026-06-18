-- L1 unit test for liv.generator option emit (pure Lua). Turns parsed option
-- defs into a loadable metadata module + a LuaLS annotation file for a named
-- class (one class per availability namespace: common / vim / nvim).
local format = require("liv.generator.option.format")

local function defs()
  return {
    { name = "shiftwidth", type = "number", scope = "buffer" },
    { name = "expandtab", type = "boolean", scope = "buffer" },
    { name = "filetype", type = "string", scope = "buffer" },
  }
end

describe("liv.generator.option.format", function()
  it("emits loadable metadata keyed by option name", function()
    local out = format(defs(), "liv.std.option.Common")
    local meta = assert(load(out.meta))()
    assert.same({ type = "boolean", scope = "buffer" }, meta.expandtab)
    assert.same({ type = "number", scope = "buffer" }, meta.shiftwidth)
    assert.same({ type = "string", scope = "buffer" }, meta.filetype)
  end)

  it("emits LuaLS @field annotations under the given class, with mapped types", function()
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
    assert.is_true(a:find("expandtab", 1, true) < a:find("shiftwidth", 1, true))
  end)
end)
