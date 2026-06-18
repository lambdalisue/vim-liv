-- L1 unit test for liv.lua.text (spec 0006). Pure, editor-independent helpers
-- shared by the editor-dependent backends: splitting display content into lines,
-- and coercing a string-or-list argument into a plain list to iterate.
local text = require("liv.lua.text")

describe("text.lines", function()
  it("returns a list unchanged", function()
    assert.same({ "a", "b" }, text.lines({ "a", "b" }))
  end)

  it("splits a single string on newlines", function()
    assert.same({ "one", "two", "three" }, text.lines("one\ntwo\nthree"))
  end)

  it("returns a single-element list for a string with no newline", function()
    assert.same({ "solo" }, text.lines("solo"))
  end)

  it("preserves a trailing empty line", function()
    assert.same({ "a", "" }, text.lines("a\n"))
  end)

  it("returns a single empty line for an empty string", function()
    assert.same({ "" }, text.lines(""))
  end)
end)

describe("text.aslist", function()
  it("wraps a scalar string into a one-element list", function()
    assert.same({ "n" }, text.aslist("n"))
  end)

  it("returns a list unchanged", function()
    assert.same({ "n", "i" }, text.aslist({ "n", "i" }))
  end)
end)
