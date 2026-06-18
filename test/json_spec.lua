-- L3 integration test for liv.std.json (spec 0006), on both editors.
local json = require("liv.std.json")
local core = require("liv.core")

describe("liv.std.json (L3)", function()
  it("encodes compactly and identically on both editors", function()
    assert.equal("[1,2,3]", json.encode(core.list({ 1, 2, 3 })))
    assert.equal("{\"a\":1}", json.encode(core.dict({ a = 1 })))
    assert.equal("\"hi\"", json.encode("hi"))
  end)

  it("decodes objects and arrays to plain Lua values", function()
    assert.same({ 1, 2, 3 }, json.decode("[1,2,3]"))
    assert.same({ a = 1, b = 2 }, json.decode('{"a":1,"b":2}'))
  end)

  it("round-trips a value", function()
    assert.same({ 10, 20 }, json.decode(json.encode(core.list({ 10, 20 }))))
  end)
end)
