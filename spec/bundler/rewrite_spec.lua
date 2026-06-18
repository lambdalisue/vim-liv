-- L1 unit test for liv.bundler.rewrite. Pure, no editor.
local rewrite = require("liv.bundler.rewrite")

local function vendored(...)
  return rewrite.name_set({ ... })
end

describe("liv.bundler.rewrite", function()
  it("rewrites a vendored require to the plugin prefix", function()
    local out = rewrite.rewrite('local b = require("liv.std.buffer")', vendored("liv.std.buffer"), "mp.vendor")
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
    local out = rewrite.rewrite("require 'liv.core' .. require(\"liv.lua.path\")", vendored("liv.core", "liv.lua.path"), "mp.vendor")
    assert.equal("require 'mp.vendor.liv.core' .. require(\"mp.vendor.liv.lua.path\")", out)
  end)

  it("rewrites every occurrence", function()
    local out = rewrite.rewrite('require("liv.a")\nrequire("liv.a")', vendored("liv.a"), "p.v")
    assert.equal('require("p.v.liv.a")\nrequire("p.v.liv.a")', out)
  end)
end)
