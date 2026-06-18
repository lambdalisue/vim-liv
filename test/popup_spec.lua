-- L3 integration test for liv.std.popup (spec 0006), on both editors. The two
-- editors expose different geometry getters (nvim_win_get_config vs
-- popup_getpos), so the test normalizes them to liv's 1-based {line, col} and
-- asserts the same geometry on both. Floats are opened with no border so width is
-- the content width on either side.
local float = require("liv.std.popup")
local core = require("liv.core")

local function geom(win)
  if core.is_nvim then
    local cfg = vim.api.nvim_win_get_config(win)
    return { line = cfg.row + 1, col = cfg.col + 1, width = cfg.width, height = cfg.height }
  end
  local p = core.eval("popup_getpos(" .. win .. ")")
  return { line = p.line, col = p.col, width = p.width, height = p.height }
end

local function is_open(win)
  if core.is_nvim then
    return vim.api.nvim_win_is_valid(win)
  end
  local p = core.eval("popup_getpos(" .. win .. ")")
  return type(p) == "table" and next(p) ~= nil
end

describe("liv.std.popup (L3)", function()
  it("opens at the given position and size", function()
    local win = float.open({ "alpha", "beta" }, { line = 3, col = 5, width = 10, height = 2 })
    local g = geom(win)
    assert.equal(3, g.line)
    assert.equal(5, g.col)
    assert.equal(10, g.width)
    assert.equal(2, g.height)
    float.close(win)
  end)

  it("moves to a new position", function()
    local win = float.open({ "x" }, { line = 2, col = 2, width = 5, height = 1 })
    float.move(win, { line = 6, col = 8 })
    local g = geom(win)
    assert.equal(6, g.line)
    assert.equal(8, g.col)
    float.close(win)
  end)

  it("resizes", function()
    local win = float.open({ "x" }, { line = 2, col = 2, width = 5, height = 1 })
    float.resize(win, { width = 12, height = 3 })
    local g = geom(win)
    assert.equal(12, g.width)
    assert.equal(3, g.height)
    float.close(win)
  end)

  it("close removes the window", function()
    local win = float.open({ "x" }, { line = 2, col = 2, width = 5, height = 1 })
    float.close(win)
    assert.is_false(is_open(win))
  end)

  it("accepts a multi-line string and fits its height", function()
    local win = float.open("one\ntwo\nthree", { line = 1, col = 1, width = 6 })
    assert.equal(3, geom(win).height)
    float.close(win)
  end)
end)
