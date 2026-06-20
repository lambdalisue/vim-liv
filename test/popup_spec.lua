-- L3 integration test for liv.std.popup (spec 0006), on both editors. popup is
-- buffer-backed (denops/std parity): the caller owns a buffer and open() displays
-- it in a non-focusable overlay, so writing to the buffer updates the popup live.
-- The two editors expose different geometry getters (nvim_win_get_config vs
-- popup_getpos) and buffer getters (nvim_win_get_buf vs winbufnr), so the test
-- normalizes them to liv's 1-based {line, col}. Floats open with no border so
-- width is the content width on either side.
local popup = require("liv.std.popup")
local buffer = require("liv.std.buffer")
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

-- The lines currently DISPLAYED by the popup, read from the buffer it is bound to
-- (so writes to the caller's buffer are observed through the popup).
local function shown(win)
  if core.is_nvim then
    local buf = vim.api.nvim_win_get_buf(win)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  return core.eval("getbufline(winbufnr(" .. win .. "), 1, '$')")
end

-- A caller-owned scratch buffer holding the given lines.
local function backing(lines)
  local buf = buffer.create({ scratch = true })
  buffer.set_lines(buf, 1, 1, lines)
  return buf
end

describe("liv.std.popup (L3)", function()
  it("displays a caller buffer at the given position and size", function()
    local buf = backing({ "alpha", "beta" })
    local win = popup.open(buf, { line = 3, col = 5, width = 10, height = 2 })
    local g = geom(win)
    assert.equal(3, g.line)
    assert.equal(5, g.col)
    assert.equal(10, g.width)
    assert.equal(2, g.height)
    assert.same({ "alpha", "beta" }, shown(win))
    popup.close(win)
  end)

  it("fits its size to the buffer when width/height are omitted", function()
    local buf = backing({ "one", "two", "three" })
    local win = popup.open(buf, { line = 1, col = 1 })
    local g = geom(win)
    assert.equal(3, g.height)
    assert.equal(5, g.width) -- widest line ("three")
    popup.close(win)
  end)

  it("follows live edits to the backing buffer", function()
    local buf = backing({ "before" })
    local win = popup.open(buf, { line = 2, col = 2, width = 12, height = 2 })
    buffer.set_lines(buf, 1, 1, { "after", "added" })
    assert.same({ "after", "added" }, shown(win))
    popup.close(win)
  end)

  it("moves to a new position", function()
    local win = popup.open(backing({ "x" }), { line = 2, col = 2, width = 5, height = 1 })
    popup.move(win, { line = 6, col = 8 })
    local g = geom(win)
    assert.equal(6, g.line)
    assert.equal(8, g.col)
    popup.close(win)
  end)

  it("resizes", function()
    local win = popup.open(backing({ "x" }), { line = 2, col = 2, width = 5, height = 1 })
    popup.resize(win, { width = 12, height = 3 })
    local g = geom(win)
    assert.equal(12, g.width)
    assert.equal(3, g.height)
    popup.close(win)
  end)

  it("config reconfigures title, size, and position in place", function()
    local win = popup.open(backing({ "x" }), { line = 2, col = 2, width = 5, height = 1 })
    popup.config(win, { line = 4, col = 7, width = 9, height = 2 })
    local g = geom(win)
    assert.equal(4, g.line)
    assert.equal(7, g.col)
    assert.equal(9, g.width)
    assert.equal(2, g.height)
    popup.close(win)
  end)

  -- The popup's normal/background highlight, normalized across editors.
  local function normal_hl(win)
    if core.is_nvim then
      return core.eval("nvim_get_option_value('winhighlight', {'win': " .. win .. "})")
    end
    return core.eval("popup_getoptions(" .. win .. ").highlight")
  end

  it(
    "defaults the background to Normal (not Vim's Pmenu) and honours a custom highlight",
    function()
      local default_win = popup.open(backing({ "x" }), { line = 1, col = 1 })
      -- Neovim carries it as a winhighlight remap; Vim as the popup 'highlight' option.
      if core.is_nvim then
        assert.is_true(normal_hl(default_win):find("NormalFloat:Normal", 1, true) ~= nil)
      else
        assert.equal("Normal", normal_hl(default_win))
      end
      popup.close(default_win)

      local custom_win =
        popup.open(backing({ "x" }), { line = 1, col = 1, highlight = { normal = "Comment" } })
      if core.is_nvim then
        assert.is_true(normal_hl(custom_win):find("NormalFloat:Comment", 1, true) ~= nil)
      else
        assert.equal("Comment", normal_hl(custom_win))
      end
      popup.close(custom_win)
    end
  )

  it("honours anchor, zindex (and relative on Neovim) like denops/std", function()
    local win = popup.open(
      backing({ "x" }),
      { line = 5, col = 5, width = 4, height = 1, anchor = "SE", zindex = 120, relative = "editor" }
    )
    if core.is_nvim then
      local cfg = vim.api.nvim_win_get_config(win)
      assert.equal("SE", cfg.anchor)
      assert.equal(120, cfg.zindex)
      assert.equal("editor", cfg.relative)
    else
      local o = core.eval("popup_getoptions(" .. win .. ")")
      assert.equal("botright", o.pos) -- SE -> botright
      assert.equal(120, o.zindex)
    end
    popup.close(win)
  end)

  it("applies a custom border highlight when given", function()
    local win = popup.open(
      backing({ "x" }),
      { line = 1, col = 1, border = "single", highlight = { border = "Comment" } }
    )
    if core.is_nvim then
      assert.is_true(normal_hl(win):find("FloatBorder:Comment", 1, true) ~= nil)
    else
      local bh = core.eval("popup_getoptions(" .. win .. ").borderhighlight")
      assert.equal("Comment", bh[1])
    end
    popup.close(win)
  end)

  it("close removes the window but leaves the caller-owned buffer alive", function()
    local buf = backing({ "x" })
    local win = popup.open(buf, { line = 2, col = 2, width = 5, height = 1 })
    popup.close(win)
    assert.is_false(is_open(win))
    -- The buffer is the caller's; closing the popup must not wipe it.
    assert.same({ "x" }, buffer.lines(buf, 1, 1))
  end)
end)
