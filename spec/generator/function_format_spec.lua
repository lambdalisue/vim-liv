-- L1 unit test for liv.generator function emit (pure Lua). Groups arity variants
-- per name, merges them (superset params with optionality, unioned return type),
-- and emits a LuaLS @meta annotation file declaring `class_name` with one typed
-- @field per function. Functions need no runtime metadata (the runtime forwards
-- any name to core.call), so only annotations are emitted.
local format = require("liv.generator.function.format")

describe("liv.generator.function.format", function()
  it("emits one typed @field per function under the class", function()
    local out = format({
      { name = "abs", params = { { name = "expr", optional = false } }, rettype = "number" },
    }, "liv.std.function.Common")
    assert.is_true(out:find("---@meta", 1, true) ~= nil)
    assert.is_true(out:find("---@class liv.std.function.Common", 1, true) ~= nil)
    assert.is_true(out:find("---@field abs fun(expr: any): number", 1, true) ~= nil)
  end)

  it("merges arity variants: superset params, optionality, unioned return", function()
    local out = format({
      { name = "getline", params = { { name = "lnum", optional = false } }, rettype = "string" },
      {
        name = "getline",
        params = { { name = "lnum", optional = false }, { name = "end", optional = false } },
        rettype = "any[]",
      },
    }, "liv.std.function.Common")
    -- lnum required (in both), end optional (only the 2-arg variant), return unioned;
    -- `end` is a Lua keyword so it is renamed to end_.
    assert.is_true(out:find("---@field getline fun(lnum: any, end_?: any): any[]|string", 1, true) ~= nil)
  end)

  it("marks a bracketed param optional", function()
    local out = format({
      {
        name = "has",
        params = { { name = "feature", optional = false }, { name = "check", optional = true } },
        rettype = "integer",
      },
    }, "C")
    assert.is_true(out:find("---@field has fun(feature: any, check?: any): integer", 1, true) ~= nil)
  end)

  it("handles a no-argument function", function()
    local out = format({
      { name = "localtime", params = {}, rettype = "integer" },
    }, "C")
    assert.is_true(out:find("---@field localtime fun(): integer", 1, true) ~= nil)
  end)
end)
