-- L1 unit test for liv.bundler.vendor with in-memory fakes. Pure, no editor.
local vendor = require("liv.bundler.vendor")

describe("liv.bundler.vendor", function()
  it("vendors the closure with rewritten requires and writes a lockfile", function()
    local sources = {
      ["liv.std.buffer"] = 'local core = require("liv.core")\nreturn function() end',
      ["liv.core"] = "return { is_nvim = false }",
    }
    local relpaths = {
      ["liv.std.buffer"] = "liv/std/buffer/init.lua",
      ["liv.core"] = "liv/core.lua",
    }
    local files, cleaned = {}, {}
    local fs = {
      write = function(p, c)
        files[p] = c
      end,
      clean = function(d)
        cleaned[#cleaned + 1] = d
      end,
    }
    local resolver = {
      read = function(n)
        return sources[n]
      end,
      locate = function(n)
        return relpaths[n]
      end,
    }

    local res = vendor.vendor({
      roots = { "liv.std.buffer" },
      resolver = resolver,
      fs = fs,
      target = "/tmp/mp",
      plugin = "mp",
      source = "path",
    })

    -- the closure pulled in liv.core transitively
    assert.same({ "liv.core", "liv.std.buffer" }, res.modules)
    -- the vendor root was cleaned exactly once
    assert.same({ "/tmp/mp/lua/mp/vendor" }, cleaned)
    -- buffer's require was rewritten to the plugin prefix
    assert.equal(
      'local core = require("mp.vendor.liv.core")\nreturn function() end',
      files["/tmp/mp/lua/mp/vendor/liv/std/buffer/init.lua"]
    )
    -- core had no vendored requires, copied verbatim
    assert.equal("return { is_nvim = false }", files["/tmp/mp/lua/mp/vendor/liv/core.lua"])
    -- a lockfile was written at the plugin root
    assert.is_not_nil(files["/tmp/mp/liv.lock"])
  end)
end)
