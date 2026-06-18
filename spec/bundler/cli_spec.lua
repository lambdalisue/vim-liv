-- L1 unit test for liv.bundler.cli. Pure, no editor (resolver/fs injected).
local cli = require("liv.bundler.cli")

describe("liv.bundler.cli.parse", function()
  it("separates module roots from --key=value flags", function()
    local o = cli.parse({ "liv.std.buffer", "liv.core", "--source=path", "--from=/x", "--plugin=mp" })
    assert.same({ "liv.std.buffer", "liv.core" }, o.roots)
    assert.equal("path", o.source)
    assert.equal("/x", o.from)
    assert.equal("mp", o.plugin)
  end)
end)

describe("liv.bundler.cli.main", function()
  it("orchestrates vendor with an injected resolver and fs", function()
    local sources = { ["liv.std.x"] = 'require("liv.core")', ["liv.core"] = "return {}" }
    local relpaths = { ["liv.std.x"] = "liv/std/x.lua", ["liv.core"] = "liv/core.lua" }
    local files = {}
    local res = cli.main({ roots = { "liv.std.x" }, plugin = "mp", to = "/t" }, {
      fs = {
        write = function(p, c)
          files[p] = c
        end,
        clean = function() end,
      },
      resolver = {
        read = function(n)
          return sources[n]
        end,
        locate = function(n)
          return relpaths[n]
        end,
      },
    })
    assert.same({ "liv.core", "liv.std.x" }, res.modules)
    assert.equal('require("mp.vendor.liv.core")', files["/t/lua/mp/vendor/liv/std/x.lua"])
  end)

  it("requires modules and a plugin name", function()
    local stub = { resolver = { read = function() end, locate = function() end }, fs = {} }
    assert.is_false((pcall(cli.main, { roots = {}, plugin = "mp" }, stub)))
    assert.is_false((pcall(cli.main, { roots = { "x" } }, stub)))
  end)
end)
