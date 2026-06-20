-- L3 integration test for liv.std.text (spec 0006), on both editors. Asserts the
-- editor's real strdisplaywidth backs `width`, and that the pure algorithms
-- (truncate/pad/align/wrap from liv.lua.text) behave correctly once wired to it.
local text = require("liv.std.text")

describe("liv.std.text (L3)", function()
  it("measures display columns via the real strdisplaywidth", function()
    assert.equal(3, text.width("abc"))
    -- Fullwidth kana are two columns each on both editors.
    assert.equal(4, text.width("あい"))
  end)

  it("truncates wide text within the budget on a code-point boundary", function()
    local out = text.truncate("ありがとう", 6, { ellipsis = "" })
    assert.is_true(text.width(out) <= 6)
    -- Three kana = width 6; the slice must not split a multi-byte code point.
    assert.equal("ありが", out)
  end)

  it("counts the ellipsis width when truncating", function()
    local out = text.truncate("ありがとう", 6)
    assert.is_true(text.width(out) <= 6)
    -- Default ellipsis "…" is two columns, leaving four for two kana.
    assert.equal("あり…", out)
  end)

  it("pads to a display width accounting for wide characters", function()
    assert.equal("あ  ", text.pad("あ", 4))
    assert.equal("ab   ", text.pad("ab", 5))
  end)

  it("aligns within a display width", function()
    assert.equal("   ab", text.align("ab", 5, { side = "right" }))
  end)

  it("wraps so each line fits the display width", function()
    local lines = text.wrap("the quick brown fox", 9)
    for _, line in ipairs(lines) do
      assert.is_true(text.width(line) <= 9)
    end
    assert.equal("the quick brown fox", table.concat(lines, " "))
  end)
end)
