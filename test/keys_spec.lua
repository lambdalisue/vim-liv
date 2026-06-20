-- L3 integration test for liv.std.keys (spec 0006), on both editors. Both the
-- encode (notation -> real terminal bytes) and feed (type encoded keys into the
-- input stream) paths run for real here: feed with `immediate=true` appends the
-- "x" flag, which processes the typeahead synchronously even under headless, so a
-- buffer edit driven by fed keys is observable in the same test (the proven
-- feedkeys-"x" pattern from ui_spec's select case).
local keys = require("liv.std.keys")
local buffer = require("liv.std.buffer")
local core = require("liv.core")

describe("liv.std.keys encode (L3)", function()
  it("translates key notation into real terminal bytes", function()
    -- <CR> is at least one byte and is NOT the literal notation text anymore.
    assert.is_true(#keys.encode("<CR>") >= 1)
    assert.are_not.equal("<CR>", keys.encode("<CR>"))
  end)

  it("passes plain text through unchanged", function()
    assert.equal("abc", keys.encode("abc"))
  end)

  it("encodes <Esc> to the single escape byte 0x1b", function()
    assert.equal(string.char(0x1b), keys.encode("<Esc>"))
  end)

  it("encodes <lt> to a literal less-than", function()
    assert.equal("<", keys.encode("<lt>"))
  end)
end)

describe("liv.std.keys feed (L3)", function()
  before_each(function()
    -- A fresh, entered, empty buffer (the buffer_spec before_each pattern).
    core.cmd("enew!")
  end)

  it("feeds notation keys that edit the buffer (immediate)", function()
    -- Insert "hello" then escape; with immediate the typeahead is consumed now.
    keys.feed("ihello<Esc>", { immediate = true })
    assert.equal("hello", buffer.lines(0, 1, 1)[1])
  end)

  it("send is feed with immediate defaulted on", function()
    keys.send("iworld<Esc>")
    assert.equal("world", buffer.lines(0, 1, 1)[1])
  end)
end)
