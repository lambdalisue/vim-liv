-- L3 integration test for liv.std.window (spec 0006). Runs the real backend on
-- both editors and asserts identical Lua values — in particular that {line, col}
-- is 1-based on both, despite Neovim's native 0-based column.
local window = require("liv.std.window")
local buffer = require("liv.std.buffer")
local core = require("liv.core")

describe("liv.std.window (L3)", function()
  before_each(function()
    core.cmd("silent! only") -- collapse to a single window
    core.cmd("enew!")
    core.call("setline", 1, core.list({ "abcdef", "ghijkl", "mnopqr" }))
  end)

  it("current returns a window id", function()
    assert.is_number(window.current())
  end)

  it("buffer returns the buffer shown in the window", function()
    assert.is_number(window.buffer(0))
    assert.equal(window.buffer(0), window.buffer(window.current()))
  end)

  it("cursor / set_cursor round-trip a 1-based {line, col}", function()
    window.set_cursor(0, { 2, 3 })
    assert.same({ 2, 3 }, window.cursor(0))
    window.set_cursor(0, { 3, 1 })
    assert.same({ 3, 1 }, window.cursor(0))
  end)

  it("the current window's buffer matches the current buffer", function()
    assert.equal(buffer.name(0), buffer.name(window.buffer(window.current())))
  end)

  it("all lists the current tabpage's windows", function()
    assert.equal(1, #window.all())
    core.cmd("split")
    assert.equal(2, #window.all())
  end)

  it("size returns a positive {width, height}", function()
    local sz = window.size(0)
    assert.is_true(sz[1] > 0)
    assert.is_true(sz[2] > 0)
  end)

  it("focus changes the current window", function()
    core.cmd("split")
    local wins = window.all()
    window.focus(wins[1])
    assert.equal(wins[1], window.current())
    window.focus(wins[2])
    assert.equal(wins[2], window.current())
  end)

  it("close removes a window from the tabpage", function()
    core.cmd("split")
    assert.equal(2, #window.all())
    local cur = window.current()
    local wins = window.all()
    window.close(wins[1] == cur and wins[2] or wins[1])
    assert.equal(1, #window.all())
  end)

  it("valid reports whether a window exists (never raises)", function()
    assert.is_true(window.valid(0))
    assert.is_true(window.valid(window.current()))
    assert.is_false(window.valid(999999))
  end)

  it("buffer raises the same liv error on an invalid window on both editors", function()
    local ok, err = pcall(window.buffer, 999999)
    assert.is_false(ok)
    assert.is_true(
      tostring(err):find("liv.std.window.buffer: invalid window id", 1, true) ~= nil,
      "expected liv-branded invalid-window error, got: " .. tostring(err)
    )
  end)

  it("set_cursor raises a uniform liv error on an invalid window on both editors", function()
    -- An invalid handle passed to an OPERATION is a failure, not a missing value:
    -- it must raise on both editors (Vim's win_execute would silently no-op).
    local ok, err = pcall(window.set_cursor, 999999, { 1, 1 })
    assert.is_false(ok)
    assert.is_true(
      tostring(err):find("liv.std.window: invalid window id", 1, true) ~= nil,
      "expected liv-branded invalid-window error, got: " .. tostring(err)
    )
  end)

  it("open displays a caller-owned buffer in a new split window", function()
    local buf = buffer.create({ scratch = true })
    buffer.set_lines(buf, 1, 1, { "sidebar" })
    local before = #window.all()
    local win = window.open(buf, { split = "right", size = 20 })
    assert.is_true(window.valid(win))
    assert.equal(before + 1, #window.all())
    assert.equal(buf, window.buffer(win)) -- it shows the caller's buffer
    assert.equal(win, window.current()) -- focus moves to the new window by default
    window.close(win)
  end)

  it("open with focus=false leaves the current window unchanged", function()
    local origin = window.current()
    local buf = buffer.create({ scratch = true })
    local win = window.open(buf, { split = "below", focus = false })
    assert.is_true(window.valid(win))
    assert.equal(origin, window.current()) -- focus stayed put
    window.close(win)
  end)

  it("set_buffer swaps the buffer shown in a window", function()
    local first = buffer.create({ scratch = true })
    buffer.set_lines(first, 1, 1, { "first" })
    local win = window.open(first, { split = "below" })
    local second = buffer.create({ scratch = true })
    buffer.set_lines(second, 1, 1, { "second" })
    window.set_buffer(win, second)
    assert.equal(second, window.buffer(win))
    window.close(win)
  end)

  it("set_buffer raises a uniform liv error on an invalid window on both editors", function()
    local buf = buffer.create({ scratch = true })
    local ok, err = pcall(window.set_buffer, 999999, buf)
    assert.is_false(ok)
    assert.is_true(
      tostring(err):find("liv.std.window: invalid window id", 1, true) ~= nil,
      "expected liv-branded invalid-window error, got: " .. tostring(err)
    )
  end)
end)
