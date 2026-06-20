-- L1 unit test for liv.lua.text (spec 0006). Pure, editor-independent helpers
-- shared by the editor-dependent backends: splitting display content into lines,
-- and coercing a string-or-list argument into a plain list to iterate.
--
-- The module is split into two concern leaves under text/ — coerce (lines/aslist)
-- and width (chars/truncate/pad/align/wrap) — re-exposed flat by the barrel. The
-- coercion group is exercised through the leaf it now lives in; the display-width
-- group through its leaf; and the barrel is asserted to keep the flat back-compat
-- API so require("liv.lua.text") behaves exactly as before.
local coerce = require("liv.lua.text.coerce")
local text = require("liv.lua.text.width")

describe("text barrel back-compat", function()
  it("re-exposes the flat API of both concern leaves", function()
    local barrel = require("liv.lua.text")
    assert.equal(coerce.lines, barrel.lines)
    assert.equal(coerce.aslist, barrel.aslist)
    assert.equal(text.chars, barrel.chars)
    assert.equal(text.truncate, barrel.truncate)
    assert.equal(text.pad, barrel.pad)
    assert.equal(text.align, barrel.align)
    assert.equal(text.wrap, barrel.wrap)
  end)
end)

describe("coerce.lines", function()
  it("returns a list unchanged", function()
    assert.same({ "a", "b" }, coerce.lines({ "a", "b" }))
  end)

  it("splits a single string on newlines", function()
    assert.same({ "one", "two", "three" }, coerce.lines("one\ntwo\nthree"))
  end)

  it("returns a single-element list for a string with no newline", function()
    assert.same({ "solo" }, coerce.lines("solo"))
  end)

  it("preserves a trailing empty line", function()
    assert.same({ "a", "" }, coerce.lines("a\n"))
  end)

  it("returns a single empty line for an empty string", function()
    assert.same({ "" }, coerce.lines(""))
  end)
end)

describe("coerce.aslist", function()
  it("wraps a scalar string into a one-element list", function()
    assert.same({ "n" }, coerce.aslist("n"))
  end)

  it("returns a list unchanged", function()
    assert.same({ "n", "i" }, coerce.aslist({ "n", "i" }))
  end)
end)

-- A fake display-width function used to drive the pure algorithms without an
-- editor. It iterates code points (NOT bytes): an ASCII leading byte counts as
-- one column, a multi-byte leading byte (>127) counts as two — a faithful proxy
-- for the real strdisplaywidth, where a fullwidth kana like "あ" is two columns.
local function fake_width(s)
  local w = 0
  for _, ch in text.chars(s) do
    if string.byte(ch) > 127 then
      w = w + 2
    else
      w = w + 1
    end
  end
  return w
end

describe("text.chars", function()
  it("iterates ASCII as one-byte code points", function()
    local out = {}
    for _, ch in text.chars("abc") do
      out[#out + 1] = ch
    end
    assert.same({ "a", "b", "c" }, out)
  end)

  it("iterates multi-byte UTF-8 on code-point boundaries", function()
    local out = {}
    for _, ch in text.chars("aあい") do
      out[#out + 1] = ch
    end
    assert.same({ "a", "あ", "い" }, out)
  end)

  it("reassembles to the original string", function()
    local parts = {}
    for _, ch in text.chars("ありがとう") do
      parts[#parts + 1] = ch
    end
    assert.equal("ありがとう", table.concat(parts))
  end)
end)

describe("fake_width (sanity)", function()
  it("counts ASCII as one column each", function()
    assert.equal(3, fake_width("abc"))
  end)

  it("counts fullwidth code points as two columns each", function()
    assert.equal(4, fake_width("あい"))
    assert.equal(10, fake_width("ありがとう"))
  end)
end)

describe("text.truncate", function()
  it("returns the string unchanged when it already fits", function()
    assert.equal("abc", text.truncate("abc", 5, nil, fake_width))
  end)

  it("truncates ASCII and appends the ellipsis within the budget", function()
    local out = text.truncate("abcdefgh", 5, { ellipsis = "..." }, fake_width)
    assert.equal("ab...", out)
    assert.is_true(fake_width(out) <= 5)
  end)

  it("never exceeds the budget and keeps valid UTF-8 when slicing kana", function()
    local out = text.truncate("ありがとう", 4, { ellipsis = "" }, fake_width)
    assert.is_true(fake_width(out) <= 4)
    -- Two kana = width 4; slicing must land on a code-point boundary.
    assert.equal("あり", out)
  end)

  it("counts the ellipsis width when truncating wide text", function()
    local out = text.truncate("ありがとう", 6, { ellipsis = "…" }, fake_width)
    -- "…" is width 2, leaving 4 columns = two kana.
    assert.equal("あり…", out)
    assert.is_true(fake_width(out) <= 6)
  end)

  it("truncates from the left when side is left", function()
    local out = text.truncate("abcdefgh", 5, { side = "left", ellipsis = "..." }, fake_width)
    assert.equal("...gh", out)
    assert.is_true(fake_width(out) <= 5)
  end)

  it("truncates in the middle when side is center", function()
    local out = text.truncate("abcdefghij", 7, { side = "center", ellipsis = "..." }, fake_width)
    assert.is_true(fake_width(out) <= 7)
    assert.equal("ab...ij", out)
  end)

  it("hard-truncates without ellipsis when the ellipsis cannot fit", function()
    local out = text.truncate("abcdef", 2, { ellipsis = "..." }, fake_width)
    assert.is_true(fake_width(out) <= 2)
    assert.equal("ab", out)
  end)
end)

describe("text.pad", function()
  it("pads on the right by default", function()
    assert.equal("ab   ", text.pad("ab", 5, nil, fake_width))
  end)

  it("pads on the left", function()
    assert.equal("   ab", text.pad("ab", 5, { side = "left" }, fake_width))
  end)

  it("pads on both sides", function()
    assert.equal(" ab  ", text.pad("ab", 5, { side = "both" }, fake_width))
  end)

  it("accounts for wide code points when measuring", function()
    -- "あ" is two columns, so reaching width 4 needs two fill columns.
    assert.equal("あ  ", text.pad("あ", 4, nil, fake_width))
  end)

  it("returns the string unchanged when already at or above width", function()
    assert.equal("abcde", text.pad("abcde", 5, nil, fake_width))
    assert.equal("abcdef", text.pad("abcdef", 5, nil, fake_width))
  end)

  it("pads with a custom fill character", function()
    assert.equal("ab...", text.pad("ab", 5, { fill = "." }, fake_width))
  end)
end)

describe("text.align", function()
  it("left-aligns by padding on the right", function()
    assert.equal("ab   ", text.align("ab", 5, { side = "left" }, fake_width))
  end)

  it("right-aligns by padding on the left", function()
    assert.equal("   ab", text.align("ab", 5, { side = "right" }, fake_width))
  end)

  it("center-aligns by padding both sides", function()
    assert.equal(" ab  ", text.align("ab", 5, { side = "center" }, fake_width))
  end)
end)

describe("text.wrap", function()
  it("returns a single line when it already fits", function()
    assert.same({ "hello" }, text.wrap("hello", 10, fake_width))
  end)

  it("breaks on spaces so each line fits the width", function()
    local lines = text.wrap("the quick brown fox", 9, fake_width)
    for _, line in ipairs(lines) do
      assert.is_true(fake_width(line) <= 9)
    end
    -- Space-broken lines rejoin with a single space to recover the input.
    assert.equal("the quick brown fox", table.concat(lines, " "))
  end)

  it("hard-breaks a long run with no spaces on code-point boundaries", function()
    local lines = text.wrap("ありがとうございます", 4, fake_width)
    for _, line in ipairs(lines) do
      assert.is_true(fake_width(line) <= 4)
    end
    -- A run with no break points rejoins with no separator and stays valid UTF-8.
    assert.equal("ありがとうございます", table.concat(lines))
  end)
end)
