-- L3 integration test for liv.std.cursor (spec 0006), on both editors. A real
-- terminal cursor cannot be observed headless, so the tests assert the OBSERVABLE
-- editor STATE the mechanism manipulates: Neovim's 'guicursor', Vim's 't_ve'
-- termcap. The two editors degrade asymmetrically under a headless harness:
--
--   * Neovim has a non-empty default 'guicursor' even headless, so "after hide()
--     it differs from the saved original" is a meaningful assertion there.
--   * Headless Vim leaves the terminal termcap empty (&t_ve == &t_vi == ""), so a
--     "differs after hide" assertion would be vacuously false. The Vim arm instead
--     asserts the RELATIONSHIP the mechanism establishes (&t_ve == &t_vi after
--     hide) plus the round-trip restore — both hold whether termcap is populated
--     (real terminal) or empty (headless).
--
-- show() must restore the exact prior state, and the hide/show pair must be
-- idempotent (double-hide / double-show / show-before-hide are no-ops net of
-- state), which the round-trip assertions below pin down.
local cursor = require("liv.std.cursor")
local has = require("liv.std.has")
local core = require("liv.core")

describe("liv.std.cursor (L3)", function()
  it("is reported available on this editor", function()
    assert.is_true(has("cursor.hide"))
  end)

  if core.is_nvim then
    it("hide() points 'guicursor' away from the saved original; show() restores it", function()
      local original = core.eval("&guicursor")

      cursor.hide()
      assert.are_not.equal(original, core.eval("&guicursor"))

      cursor.show()
      assert.equal(original, core.eval("&guicursor"))
    end)

    it("is idempotent: hide;hide;show;show leaves 'guicursor' at the original", function()
      local original = core.eval("&guicursor")

      cursor.hide()
      cursor.hide()
      cursor.show()
      cursor.show()

      assert.equal(original, core.eval("&guicursor"))
    end)

    it("show() before any hide() is a safe no-op", function()
      local original = core.eval("&guicursor")
      cursor.show()
      assert.equal(original, core.eval("&guicursor"))
    end)
  else
    it("hide() sets 't_ve' to the invisible termcap; show() restores it", function()
      local original = core.eval("&t_ve")

      cursor.hide()
      assert.equal(core.eval("&t_vi"), core.eval("&t_ve"))

      cursor.show()
      assert.equal(original, core.eval("&t_ve"))
    end)

    it("is idempotent: hide;hide;show;show leaves 't_ve' at the original", function()
      local original = core.eval("&t_ve")

      cursor.hide()
      cursor.hide()
      cursor.show()
      cursor.show()

      assert.equal(original, core.eval("&t_ve"))
    end)

    it("show() before any hide() is a safe no-op", function()
      local original = core.eval("&t_ve")
      cursor.show()
      assert.equal(original, core.eval("&t_ve"))
    end)
  end
end)
