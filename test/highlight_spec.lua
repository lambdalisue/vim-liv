-- L3 integration test for liv.std.highlight (spec 0006), on both editors. Defines
-- a named group with fg+bg+bold then reads the stored definition back through the
-- editor's own API and asserts the colors and attribute survived. Readback types
-- differ per editor (Neovim returns integers/booleans, Vim returns "#rrggbb"
-- strings), so the assertions branch. Distinct fg/bg make a swap regression
-- visible.
local highlight = require("liv.std.highlight")
local has = require("liv.std.has")
local core = require("liv.core")

describe("liv.std.highlight (L3)", function()
  it("is reported available on this editor", function()
    assert.is_true(has("highlight"))
  end)

  it("sets fg, bg and bold on a named group, readable back", function()
    highlight.set("LivHighlightTest", { fg = 0xff0000, bg = 0x0000ff, bold = true })

    if core.is_nvim then
      local hl = vim.api.nvim_get_hl(0, { name = "LivHighlightTest" })
      assert.equal(0xff0000, hl.fg)
      assert.equal(0x0000ff, hl.bg)
      assert.is_true(hl.bold)
    else
      local id = core.eval("synIDtrans(hlID('LivHighlightTest'))")
      assert.equal("#ff0000", core.call("synIDattr", id, "fg#", "gui"))
      assert.equal("#0000ff", core.call("synIDattr", id, "bg#", "gui"))
      assert.equal("1", core.call("synIDattr", id, "bold", "gui"))
    end
  end)

  it("accepts a '#rrggbb' string color the same as an integer", function()
    highlight.set("LivHighlightTestStr", { fg = "#00ff00" })

    if core.is_nvim then
      local hl = vim.api.nvim_get_hl(0, { name = "LivHighlightTestStr" })
      assert.equal(0x00ff00, hl.fg)
    else
      local id = core.eval("synIDtrans(hlID('LivHighlightTestStr'))")
      assert.equal("#00ff00", core.call("synIDattr", id, "fg#", "gui"))
    end
  end)
end)
