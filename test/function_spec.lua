-- L3 integration test for liv.std.function (spec 0006). The forwarding metatable turns
-- fn.<name>(...) into core.call("<name>", ...) with marshaling, on both editors.
local fn = require("liv.std.function")
local core = require("liv.core")

describe("liv.std.function (L3)", function()
  it("forwards a scalar builtin call", function()
    assert.equal(5, fn.abs(-5))
  end)

  it("returns a list result as a plain Lua table", function()
    assert.same({ 0, 1, 2 }, fn.range(3))
  end)

  it("round-trips a list argument through marshaling", function()
    assert.same({ 3, 2, 1 }, fn.reverse(core.list({ 1, 2, 3 })))
  end)

  it("memoizes the wrapper per name (stable identity)", function()
    assert.equal(fn.abs, fn.abs)
  end)
end)
