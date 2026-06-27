-- L1 unit test for liv.bundler.rewrite. Pure, no editor.
local rewrite = require("liv.bundler.rewrite")

local function vendored(...)
  return rewrite.name_set({ ... })
end

describe("liv.bundler.rewrite", function()
  it("rewrites a vendored require to the plugin prefix", function()
    local out = rewrite.rewrite(
      'local b = require("liv.std.buffer")',
      vendored("liv.std.buffer"),
      "mp.vendor"
    )
    assert.equal('local b = require("mp.vendor.liv.std.buffer")', out)
  end)

  it("leaves non-vendored requires (plugin-own, external) untouched", function()
    local src = 'require("liv.core") require("mp.util") require("third.party")'
    local out = rewrite.rewrite(src, vendored("liv.core"), "mp.vendor")
    assert.equal('require("mp.vendor.liv.core") require("mp.util") require("third.party")', out)
  end)

  it("matches on the exact name, not a substring", function()
    -- "liv" is vendored but "livmore" must not be touched
    local out = rewrite.rewrite('require("livmore.x") require("liv")', vendored("liv"), "mp.vendor")
    assert.equal('require("livmore.x") require("mp.vendor.liv")', out)
  end)

  it("handles both quote styles and the parenthesis-less form", function()
    local out = rewrite.rewrite(
      "require 'liv.core' .. require(\"liv.lua.path\")",
      vendored("liv.core", "liv.lua.path"),
      "mp.vendor"
    )
    assert.equal("require 'mp.vendor.liv.core' .. require(\"mp.vendor.liv.lua.path\")", out)
  end)

  it("rewrites every occurrence", function()
    local out = rewrite.rewrite('require("liv.a")\nrequire("liv.a")', vendored("liv.a"), "p.v")
    assert.equal('require("p.v.liv.a")\nrequire("p.v.liv.a")', out)
  end)

  describe("rewrite_autoload", function()
    it("prefixes a vendored autoload #-name reference", function()
      local out = rewrite.rewrite_autoload(
        'core.call("liv#std#dispatch#Invoke", id)',
        { "liv#std#dispatch" },
        "mp#vendor"
      )
      assert.equal('core.call("mp#vendor#liv#std#dispatch#Invoke", id)', out)
    end)

    it("rewrites multiple stems and every occurrence", function()
      local src = '"liv#std#process#Start" "liv#std#dispatch#Invoke" "liv#std#process#Send"'
      local out =
        rewrite.rewrite_autoload(src, { "liv#std#process", "liv#std#dispatch" }, "mp#vendor")
      assert.equal(
        '"mp#vendor#liv#std#process#Start" "mp#vendor#liv#std#dispatch#Invoke" "mp#vendor#liv#std#process#Send"',
        out
      )
    end)

    it("requires a trailing # so a bare stem (no function segment) is untouched", function()
      -- only "stem#..." occurrences are rewritten; a lone "liv#std#dispatch" is not
      local out =
        rewrite.rewrite_autoload('"liv#std#dispatch"', { "liv#std#dispatch" }, "mp#vendor")
      assert.equal('"liv#std#dispatch"', out)
    end)

    it("rewrites mid-string and comment occurrences (over-matching is safe)", function()
      -- The rewrite is a deliberate whole-source replace, NOT quote-anchored: a `#`
      -- is illegal in Lua code, so it only ever lands inside a string or a comment.
      -- A mid-string call MUST be rewritten (anchoring on a quote would miss it and
      -- leave a colliding name); a comment rewrite is harmless. Both are asserted.
      local src = '-- see liv#std#dispatch#Invoke\nx = "<Cmd>call liv#std#dispatch#Invoke(1)<CR>"'
      local out = rewrite.rewrite_autoload(src, { "liv#std#dispatch" }, "mp#vendor")
      assert.equal(
        '-- see mp#vendor#liv#std#dispatch#Invoke\nx = "<Cmd>call mp#vendor#liv#std#dispatch#Invoke(1)<CR>"',
        out
      )
    end)
  end)
end)
