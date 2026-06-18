-- L3 integration test for liv.std.option (spec 0006). The key contract: a
-- boolean option reads back as a Lua boolean on BOTH editors (Vim natively
-- reports 0/1), via property access and the raw API.
local option = require("liv.std.option")
local core = require("liv.core")

describe("liv.std.option (L3)", function()
  it("global boolean reads back as a Lua boolean on both editors", function()
    option.g.ignorecase = true
    assert.equal(true, option.g.ignorecase)
    option.g.ignorecase = false
    assert.equal(false, option.g.ignorecase)
  end)

  it("global number round-trips", function()
    option.g.history = 123
    assert.equal(123, option.g.history)
  end)

  it("global string round-trips (with quotes handled)", function()
    option.g.wildignore = "*.o,*.obj"
    assert.equal("*.o,*.obj", option.g.wildignore)
  end)

  it("buffer-local boolean round-trips as a Lua boolean", function()
    option.b.expandtab = true
    assert.is_true(option.b.expandtab)
    option.b.expandtab = false
    assert.is_false(option.b.expandtab)
  end)

  it("window-local boolean round-trips", function()
    option.w.number = true
    assert.is_true(option.w.number)
  end)

  it("the raw get/set API works alongside property access", function()
    option.g.set("history", 50)
    assert.equal(50, option.g.get("history"))
    assert.equal(50, option.g.history)
  end)

  it("buffer scope set/get targets a NON-current buffer via an optional handle", function()
    local buffer = require("liv.std.buffer")
    local other = buffer.create({})
    -- keep this buffer NON-current; target it explicitly via the trailing arg.
    option.b.set("expandtab", false) -- current buffer baseline
    option.b.set("expandtab", true, other)
    assert.is_true(option.b.get("expandtab", other))
    option.b.set("expandtab", false, other)
    assert.is_false(option.b.get("expandtab", other))
    -- The no-arg form (aibo uses option.b.get/set("omnifunc")) still targets current.
    assert.is_false(option.b.get("expandtab"))
    buffer.wipe(other)
  end)

  it("window scope set/get targets a NON-current window via an optional handle", function()
    local window = require("liv.std.window")
    core.cmd("silent! only")
    core.cmd("split")
    local wins = window.all()
    local cur = window.current()
    local other = wins[1] == cur and wins[2] or wins[1]
    option.w.set("number", false, other)
    assert.is_false(option.w.get("number", other))
    option.w.set("number", true, other)
    assert.is_true(option.w.get("number", other))
    core.cmd("silent! only")
  end)
end)
