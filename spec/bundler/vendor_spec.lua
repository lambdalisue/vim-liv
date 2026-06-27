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
    -- both the lua/ vendor root and the autoload/ vendor root are cleaned (the
    -- latter unconditionally, so a re-bundle that drops all autoload deps still
    -- removes any stale relocated companions)
    assert.same({ "/tmp/mp/lua/mp/vendor", "/tmp/mp/autoload/mp/vendor" }, cleaned)
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

  it("copies a declared companion file verbatim beside its module", function()
    local sources = {
      ["liv.std.command"] = 'local d = require("liv.std._dispatch")',
      ["liv.std._dispatch"] = "-- dispatch",
    }
    local relpaths = {
      ["liv.std.command"] = "liv/std/command/init.lua",
      ["liv.std._dispatch"] = "liv/std/_dispatch.lua",
    }
    local manifests = { ["liv.std._dispatch"] = { files = { "_dispatch.vim" } } }
    local raws = { ["liv/std/_dispatch.vim"] = "vim9script\n# companion" }
    local files = {}
    local fs = {
      write = function(p, c)
        files[p] = c
      end,
      clean = function() end,
    }
    local resolver = {
      read = function(n)
        return sources[n]
      end,
      locate = function(n)
        return relpaths[n]
      end,
      manifest = function(n)
        return manifests[n]
      end,
      read_raw = function(rel)
        return raws[rel]
      end,
    }

    vendor.vendor({
      roots = { "liv.std.command" },
      resolver = resolver,
      fs = fs,
      target = "/t",
      plugin = "mp",
      source = "path",
    })

    -- the .vim was copied verbatim (no require rewriting) beside the vendored .lua
    assert.equal("vim9script\n# companion", files["/t/lua/mp/vendor/liv/std/_dispatch.vim"])
    -- and command's require was rewritten as usual
    assert.equal(
      'local d = require("mp.vendor.liv.std._dispatch")',
      files["/t/lua/mp/vendor/liv/std/command/init.lua"]
    )
  end)

  it("relocates a declared autoload companion and rewrites its #-name in .lua", function()
    local sources = {
      ["liv.std.command"] = 'local d = require("liv.std._dispatch")\nreturn "liv#std#dispatch#Invoke"',
      ["liv.std._dispatch"] = 'return "liv#std#dispatch#Register"',
    }
    local relpaths = {
      ["liv.std.command"] = "liv/std/command/init.lua",
      ["liv.std._dispatch"] = "liv/std/_dispatch.lua",
    }
    local manifests = { ["liv.std._dispatch"] = { autoload = { "liv/std/dispatch.vim" } } }
    -- autoload files are read from the source root's autoload/ (sibling of lua/)
    local raws = { ["../autoload/liv/std/dispatch.vim"] = "vim9script\n# autoload companion" }
    local files = {}
    local fs = {
      write = function(p, c)
        files[p] = c
      end,
      clean = function() end,
    }
    local resolver = {
      read = function(n)
        return sources[n]
      end,
      locate = function(n)
        return relpaths[n]
      end,
      manifest = function(n)
        return manifests[n]
      end,
      read_raw = function(rel)
        return raws[rel]
      end,
    }

    vendor.vendor({
      roots = { "liv.std.command" },
      resolver = resolver,
      fs = fs,
      target = "/t",
      plugin = "mp",
      source = "path",
    })

    -- the autoload companion was relocated under autoload/<plugin>/vendor, verbatim
    -- (its prefixes are derived at runtime from the script path, so no content edit)
    assert.equal(
      "vim9script\n# autoload companion",
      files["/t/autoload/mp/vendor/liv/std/dispatch.vim"]
    )
    -- the .lua autoload #-name references were rewritten to the relocated, prefixed
    -- names (alongside the usual require rewrite)
    assert.equal(
      'local d = require("mp.vendor.liv.std._dispatch")\nreturn "mp#vendor#liv#std#dispatch#Invoke"',
      files["/t/lua/mp/vendor/liv/std/command/init.lua"]
    )
    assert.equal(
      'return "mp#vendor#liv#std#dispatch#Register"',
      files["/t/lua/mp/vendor/liv/std/_dispatch.lua"]
    )
  end)
end)
