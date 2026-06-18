-- L1 unit test for liv.bundler.source.rtp with an in-memory fs. Pure, no editor.
local rtp = require("liv.bundler.source.rtp")

describe("liv.bundler.source.rtp", function()
  it("splits a runtimepath into lua/ roots", function()
    assert.same({ "/a/lua", "/b/c/lua" }, rtp.lua_roots("/a,/b/c"))
  end)

  it("resolves from the first root that has the module", function()
    local present = {
      ["/r2/lua/liv/core.lua"] = "CORE",
    }
    local fs = {
      exists = function(p)
        return present[p] ~= nil
      end,
      read = function(p)
        return present[p]
      end,
    }
    local r = rtp.resolver({ "/r1/lua", "/r2/lua" }, fs)
    assert.equal("liv/core.lua", r.locate("liv.core"))
    assert.equal("CORE", r.read("liv.core"))
    assert.is_nil(r.read("liv.absent"))
  end)
end)
