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
    local stub = {
      resolver = { read = function() end, locate = function() end },
      fs = {
        read = function()
          return nil
        end,
      },
    }
    assert.is_false((pcall(cli.main, { roots = {}, plugin = "mp" }, stub))) -- no roots, no lockfile
    assert.is_false((pcall(cli.main, { roots = { "x" } }, stub))) -- no plugin
  end)
end)

local lockfile = require("liv.bundler.lockfile")

describe("liv.bundler.cli.check", function()
  it("reports drift (source != lockfile hash) and missing vendor files", function()
    local sources = { ["liv.core"] = "CORE", ["liv.std.x"] = "XSRC" }
    local relpaths = { ["liv.core"] = "liv/core.lua", ["liv.std.x"] = "liv/std/x.lua" }
    local lock = lockfile.serialize({
      meta = { plugin = "mp", source = "path", from = "/src", roots = { "liv.std.x" } },
      modules = {
        ["liv.core"] = { source = "path", hash = lockfile.hash("CORE") }, -- matches source
        ["liv.std.x"] = { source = "path", hash = "00000000" }, -- stale -> drift
      },
    })
    local files = {
      ["/t/liv.lock"] = lock,
      ["/t/lua/mp/vendor/liv/core.lua"] = "present",
      -- x's vendored file is absent -> missing
    }
    local fs = {
      read = function(p)
        return files[p]
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
    local r = cli.check({ to = "/t" }, { fs = fs, resolver = resolver })
    assert.same({ "liv.std.x" }, r.drifted)
    assert.same({ "liv.std.x" }, r.missing)
    assert.is_false(r.ok)
  end)
end)

describe("liv.bundler.cli.remove", function()
  it("re-vendors with the remaining roots", function()
    local lock = lockfile.serialize({
      meta = { plugin = "mp", source = "path", from = "/src", roots = { "liv.a", "liv.b" } },
      modules = {},
    })
    local files = { ["/t/liv.lock"] = lock }
    local fs = {
      read = function(p)
        return files[p]
      end,
      write = function(p, c)
        files[p] = c
      end,
      clean = function() end,
    }
    local resolver = {
      read = function(n)
        return ({ ["liv.b"] = "return {}" })[n]
      end,
      locate = function(n)
        return ({ ["liv.b"] = "liv/b.lua" })[n]
      end,
    }
    local res = cli.remove({ roots = { "liv.a" }, to = "/t" }, { fs = fs, resolver = resolver })
    assert.same({ "liv.b" }, res.modules)
  end)
end)

describe("liv.bundler.cli.update", function()
  it("re-vendors from the lockfile and returns relevant migration notices", function()
    local lock = lockfile.serialize({
      meta = { plugin = "mp", source = "path", from = "/src", roots = { "liv.std.buffer" } },
      modules = {
        ["liv.std.buffer"] = { source = "path", hash = "x" },
        ["liv.core"] = { source = "path", hash = "y" },
      },
    })
    local files = { ["/t/liv.lock"] = lock }
    local fs = {
      read = function(p)
        return files[p]
      end,
      write = function(p, c)
        files[p] = c
      end,
      clean = function() end,
    }
    local resolver = {
      read = function(n)
        return ({ ["liv.std.buffer"] = "return {}" })[n]
      end,
      locate = function(n)
        return ({ ["liv.std.buffer"] = "liv/std/buffer/init.lua" })[n]
      end,
    }
    local res = cli.update({
      to = "/t",
      migrations = "2.0.0\n    Modules: std.buffer\n    breaking change\n",
      from_version = "1.0.0",
      to_version = "2.0.0",
    }, { fs = fs, resolver = resolver })
    assert.equal(1, #res.notices)
    assert.equal("2.0.0", res.notices[1].version)
  end)
end)
