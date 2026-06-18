-- L3 integration test for liv.std.mapping (spec 0006), on both editors. Triggers the
-- mappings with feedkeys to prove string rhs, Lua-function rhs, the context table,
-- expr mappings, and buffer-local scope all behave the same on Vim and Neovim.
local map = require("liv.std.mapping")
local core = require("liv.core")

describe("liv.std.mapping (L3)", function()
  it("maps a key to a string rhs", function()
    core.cmd("let g:liv_map_test = 0")
    map.set("n", ";a", ":let g:liv_map_test = 1<CR>")
    core.call("feedkeys", ";a", "x")
    assert.equal(1, core.eval("g:liv_map_test"))
    map.del("n", ";a")
  end)

  it("maps a key to a Lua function handler", function()
    local fired = false
    map.set("n", ";b", function()
      fired = true
    end)
    core.call("feedkeys", ";b", "x")
    assert.is_true(fired)
    map.del("n", ";b")
  end)

  it("passes count/register/mode to the handler", function()
    local got
    map.set("n", "<F10>", function(ctx)
      got = ctx
    end)
    core.call("feedkeys", core.eval([["2\"a\<F10>"]]), "x")
    assert.equal("table", type(got))
    assert.equal(2, got.count)
    assert.equal("a", got.register)
    assert.equal("n", got.mode)
    map.del("n", "<F10>")
  end)

  it("uses the handler's returned keys for an expr mapping", function()
    core.cmd("enew!")
    map.set("i", "<F9>", { expr = true }, function()
      return "INS"
    end)
    core.call("feedkeys", core.eval([["i\<F9>\<Esc>"]]), "x")
    assert.equal("INS", core.call("getline", 1))
    map.del("i", "<F9>")
    core.cmd("bwipeout!")
  end)

  it("replaces keycodes in an expr handler's return (same on both editors)", function()
    -- A handler returning the "<Right>" key-notation string must move the cursor
    -- one column right, not type the literal characters '<','R',… (Neovim does
    -- this via replace_keycodes; Vim must match).
    core.cmd("enew!")
    core.call("setline", 1, "abc")
    core.call("cursor", 1, 1)
    map.set("n", "<F7>", { expr = true }, function()
      return "<Right>"
    end)
    core.call("feedkeys", core.eval([["\<F7>"]]), "x")
    assert.equal(2, core.call("col", "."))
    map.del("n", "<F7>")
    core.cmd("bwipeout!")
  end)

  it("del removes the mapping", function()
    map.set("n", ";c", ":let g:liv_map_test = 9<CR>")
    map.del("n", ";c")
    assert.equal("", core.call("maparg", ";c", "n"))
  end)

  it("maps in several modes from a list", function()
    map.set({ "n", "i" }, "<F8>", function() end)
    assert.are_not.equal("", core.call("maparg", "<F8>", "n"))
    assert.are_not.equal("", core.call("maparg", "<F8>", "i"))
    map.del({ "n", "i" }, "<F8>")
  end)

  it("scopes a buffer mapping to the current buffer", function()
    map.set("n", "<F11>", { buffer = true }, function() end)
    assert.are_not.equal("", core.call("maparg", "<F11>", "n"))
    map.del("n", "<F11>", { buffer = true })
    assert.equal("", core.call("maparg", "<F11>", "n"))
  end)

  it("returns a subscription whose off() removes the mapping", function()
    local sub = map.set("n", "<F6>", function() end)
    assert.are_not.equal("", core.call("maparg", "<F6>", "n"))
    sub.off()
    assert.equal("", core.call("maparg", "<F6>", "n"))
  end)

  it("off() is idempotent (calling it twice is a no-op)", function()
    local sub = map.set("n", "<F5>", function() end)
    sub.off()
    sub.off()
    assert.equal("", core.call("maparg", "<F5>", "n"))
  end)

  it("off() removes every mode for a multi-mode mapping", function()
    local sub = map.set({ "n", "i" }, "<F4>", function() end)
    sub.off()
    assert.equal("", core.call("maparg", "<F4>", "n"))
    assert.equal("", core.call("maparg", "<F4>", "i"))
  end)
end)
