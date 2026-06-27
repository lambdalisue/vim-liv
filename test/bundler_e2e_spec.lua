-- L3 end-to-end test for the bundler (spec 0008), on both editors. This is the
-- proof that "install only your plugin" works: vendor liv.std.buffer (and its
-- transitive closure) from the repo source into a throwaway plugin, then load the
-- vendored copy through a package.path that points ONLY at that plugin — liv's own
-- lua/ is excluded, so a missed rewrite or a missing closure member fails hard
-- (it cannot silently fall back to the dev liv.*). Then the vendored buffer module
-- is exercised against a real buffer.
local vendor = require("liv.bundler.vendor")
local pathsrc = require("liv.bundler.source.path")
local iofs = require("liv.bundler._iofs")
local core = require("liv.core")

describe("bundler end-to-end (L3)", function()
  it("vendors liv.std.buffer and runs it from an isolated package.path", function()
    local root = assert(os.getenv("LIV_ROOT"), "LIV_ROOT not set")
    local src = root .. "/lua"
    local tmp = os.tmpname()
    os.remove(tmp)
    tmp = tmp .. ".plug"

    -- vendor: liv.std.buffer is companion-free (pure .lua closure)
    local resolver = pathsrc.resolver(src, iofs)
    local res = vendor.vendor({
      roots = { "liv.std.buffer" },
      resolver = resolver,
      fs = iofs,
      target = tmp,
      plugin = "myplug",
      source = "path",
    })
    -- the closure must include buffer, its two backends, core (+ its backends), and value
    assert.is_true(#res.modules >= 5, "closure too small: " .. table.concat(res.modules, ","))

    -- load the vendored copy in total isolation from the dev liv.*
    local saved = package.path
    package.path = tmp .. "/lua/?.lua;" .. tmp .. "/lua/?/init.lua"
    local ok, buf = pcall(require, "myplug.vendor.liv.std.buffer")
    package.path = saved
    assert.is_true(ok, "requiring the vendored module failed: " .. tostring(buf))

    -- the vendored module works against a real buffer
    core.cmd("enew!")
    core.call("setline", 1, core.list({ "vendored-line" }))
    assert.same({ "vendored-line" }, buf.lines(0, 1, 1))

    -- cleanup
    package.loaded["myplug.vendor.liv.std.buffer"] = nil
    iofs.clean(tmp)
  end)

  it("vendors via cli.main with the path source onto the real filesystem", function()
    local cli = require("liv.bundler.cli")
    local root = assert(os.getenv("LIV_ROOT"), "LIV_ROOT not set")
    local tmp = os.tmpname()
    os.remove(tmp)
    tmp = tmp .. ".cliplug"

    local res = cli.main({
      roots = { "liv.std.buffer" },
      plugin = "cp",
      to = tmp,
      source = "path",
      from = root .. "/lua",
    }, {})

    assert.is_true(#res.modules >= 5)
    -- the lockfile and a rewritten vendored file landed on disk
    assert.is_true(iofs.exists(tmp .. "/liv.lock"))
    assert.is_true(iofs.exists(tmp .. "/lua/cp/vendor/liv/std/buffer/init.lua"))
    iofs.clean(tmp)
  end)

  it("vendors a module's Vim 9 autoload companion and runs it in isolation", function()
    local root = assert(os.getenv("LIV_ROOT"), "LIV_ROOT not set")
    local tmp = os.tmpname()
    os.remove(tmp)
    tmp = tmp .. ".cmdplug"

    -- liv.std.command pulls liv.std._dispatch, whose Vim 9 autoload companion is
    -- declared in a manifest.
    local resolver = pathsrc.resolver(root .. "/lua", iofs)
    vendor.vendor({
      roots = { "liv.std.command" },
      resolver = resolver,
      fs = iofs,
      target = tmp,
      plugin = "cmdp",
      source = "path",
    })
    -- the autoload companion was relocated under the consumer's autoload/ tree, so
    -- its #-name (cmdp#vendor#liv#std#dispatch#...) matches the rewritten .lua
    assert.is_true(iofs.exists(tmp .. "/autoload/cmdp/vendor/liv/std/dispatch.vim"))

    -- load the vendored command in isolation: package.path points ONLY at the
    -- vendored lua/, and the vendored autoload/ goes on &runtimepath so Vim
    -- auto-sources the relocated companion on the first cmdp#vendor#... reference.
    core.cmd("set runtimepath^=" .. tmp)
    local saved = package.path
    package.path = tmp .. "/lua/?.lua;" .. tmp .. "/lua/?/init.lua"
    local ok, command = pcall(require, "cmdp.vendor.liv.std.command")
    package.path = saved
    assert.is_true(ok, "requiring the vendored command failed: " .. tostring(command))

    -- the vendored command actually defines and fires a user command (its rhs
    -- calls cmdp#vendor#liv#std#dispatch#Invoke — proving both the relocation and
    -- the #-name rewrite are correct end to end)
    local fired = false
    command.define("LivVendoredCmd", function()
      fired = true
    end)
    core.cmd("LivVendoredCmd")
    assert.is_true(fired)
    command.remove("LivVendoredCmd")

    package.loaded["cmdp.vendor.liv.std.command"] = nil
    -- Restore &runtimepath: this L3 suite runs many specs in one editor session,
    -- and autoload resolution now depends on runtimepath, so a leaked (now-deleted)
    -- entry would make later specs order-dependent. `-=` is the exact inverse of the
    -- `^=` above — it removes precisely the entry we prepended.
    core.cmd("set runtimepath-=" .. tmp)
    iofs.clean(tmp)
  end)
end)
