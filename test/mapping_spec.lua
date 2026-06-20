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

  it("get returns an info table for an existing mapping", function()
    map.set("n", "<Plug>(livget)", "<Nop>")
    local info = map.get("n", "<Plug>(livget)")
    assert.equal("table", type(info))
    assert.equal("<Plug>(livget)", info.lhs)
    assert.equal("n", info.mode)
    -- Flags read back as Lua booleans (not 0/1), matching liv's convention.
    assert.equal("boolean", type(info.noremap))
    assert.is_true(info.noremap)
    map.del("n", "<Plug>(livget)")
  end)

  it("get returns nil for an unmapped lhs", function()
    assert.is_nil(map.get("n", "<Plug>(livNeverMapped)"))
  end)

  it("get normalizes a modes list to its first element", function()
    map.set({ "n", "i" }, "<Plug>(livgetlist)", "<Nop>")
    local info = map.get({ "n", "i" }, "<Plug>(livgetlist)")
    assert.equal("table", type(info))
    assert.equal("n", info.mode)
    map.del({ "n", "i" }, "<Plug>(livgetlist)")
  end)

  it("get honors opts.buffer (a buffer-local query excludes a global map)", function()
    -- A global map is found by a global query, but NOT by a buffer-local query.
    map.set("n", "<Plug>(livgetscope)", "<Nop>")
    assert.is_not_nil(map.get("n", "<Plug>(livgetscope)"))
    assert.is_nil(map.get("n", "<Plug>(livgetscope)", { buffer = true }))
    map.del("n", "<Plug>(livgetscope)")
  end)

  it("get honors opts.buffer (a buffer-local map is found only with buffer=true)", function()
    -- A buffer-local map is found by a buffer-local query, but a global query
    -- (the default) rejects the buffer-local shadow.
    map.set("n", "<Plug>(livgetbuf)", { buffer = true }, "<Nop>")
    local info = map.get("n", "<Plug>(livgetbuf)", { buffer = true })
    assert.equal("table", type(info))
    assert.equal("<Plug>(livgetbuf)", info.lhs)
    assert.is_true(info.buffer)
    assert.is_nil(map.get("n", "<Plug>(livgetbuf)"))
    map.del("n", "<Plug>(livgetbuf)", { buffer = true })
  end)

  it("list includes a mapping matching mode and prefix", function()
    map.set("n", "<Plug>(livlist1)", "<Nop>")
    local found = false
    for _, info in ipairs(map.list({ mode = "n", prefix = "<Plug>(livlist" })) do
      if info.lhs == "<Plug>(livlist1)" then
        found = true
      end
    end
    assert.is_true(found)
    map.del("n", "<Plug>(livlist1)")
  end)
end)
