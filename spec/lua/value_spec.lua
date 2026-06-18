-- L1 unit test for liv.lua.value classification + tagging (spec 0005).
local value = require("liv.lua.value")

describe("liv.lua.value.classify", function()
  it("treats an explicit list tag as a list (highest priority)", function()
    -- A list tag wins even over dict-shaped contents.
    assert.equal("list", value.classify(value.list({ a = 1 })))
  end)

  it("treats an explicit dict tag as a dict (highest priority)", function()
    -- A dict tag wins even over sequence-shaped contents.
    assert.equal("dict", value.classify(value.dict({ 1, 2, 3 })))
  end)

  it("treats an empty table as a list by default", function()
    assert.equal("list", value.classify({}))
  end)

  it("treats a proper 1..n sequence as a list", function()
    assert.equal("list", value.classify({ 10, 20, 30 }))
  end)

  it("treats string keys as a dict", function()
    assert.equal("dict", value.classify({ a = 1, b = 2 }))
  end)

  it("treats a mixed table as a dict (deterministic case)", function()
    -- n=3, #t=2: not a proper sequence -> dict. Avoids implementation-defined
    -- behaviour of `#t` on genuinely sparse arrays.
    assert.equal("dict", value.classify({ 1, 2, foo = "x" }))
  end)
end)

describe("liv.lua.value tagging", function()
  it("recognises a list tag via is_list", function()
    local t = value.list({})
    assert.is_true(value.is_list(t))
    assert.is_false(value.is_dict(t))
  end)

  it("recognises a dict tag via is_dict", function()
    local t = value.dict({})
    assert.is_true(value.is_dict(t))
    assert.is_false(value.is_list(t))
  end)

  it("empty_dict() is a dict, not a list", function()
    local t = value.empty_dict()
    assert.is_true(value.is_dict(t))
    assert.equal("dict", value.classify(t))
  end)

  it("plain tables are neither tagged list nor dict", function()
    assert.is_false(value.is_list({}))
    assert.is_false(value.is_dict({}))
  end)

  it("list()/dict() preserve the underlying contents", function()
    local t = value.list({ 1, 2, 3 })
    assert.same({ 1, 2, 3 }, t)
  end)
end)

describe("liv.lua.value.NIL", function()
  it("is a stable, unique sentinel value", function()
    assert.is_not_nil(value.NIL)
    assert.equal(value.NIL, value.NIL)
  end)

  it("is distinct from an empty table and from false", function()
    assert.are_not.equal(value.NIL, {})
    assert.are_not.equal(value.NIL, false)
  end)
end)
