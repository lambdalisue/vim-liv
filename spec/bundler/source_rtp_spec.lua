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

  it("reads a module's companion from the SAME root that owns the module", function()
    -- /r1 has a stray companion but NOT the module; /r2 owns the module and has
    -- its own companion. The owning root (/r2) must win for the companion read,
    -- never the higher-priority /r1, or a vendored module would mix bodies.
    -- Keys are the literal `<root>/<rel>` paths the path resolver builds (it does
    -- not normalize the "lua/../autoload" segment — the fs would).
    local present = {
      ["/r1/lua/../autoload/liv/std/process.vim"] = "R1-STRAY",
      ["/r2/lua/liv/std/process/_vim.lua"] = "PROCESS",
      ["/r2/lua/../autoload/liv/std/process.vim"] = "R2-OWNED",
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
    -- Anchored to the owning module: reads /r2's companion, not /r1's stray copy.
    assert.equal("R2-OWNED", r.read_raw("../autoload/liv/std/process.vim", "liv.std.process._vim"))
    -- Without an owning module, read_raw falls back to first-match (/r1).
    assert.equal("R1-STRAY", r.read_raw("../autoload/liv/std/process.vim"))
  end)
end)
