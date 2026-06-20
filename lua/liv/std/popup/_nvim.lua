-- liv.std.popup Neovim backend: a scratch buffer shown in a non-focusable
-- floating window. The scratch buffer is created with bufhidden=wipe so closing
-- the window reclaims it automatically — no window->buffer registry to maintain.
-- liv's 1-based {line, col} maps to Neovim's 0-based row/col.
local text = require("liv.lua.text")

return function(core)
  local create_buf = core.marshaled(vim.api.nvim_create_buf)
  local set_lines = core.marshaled(vim.api.nvim_buf_set_lines)
  local set_opt = core.marshaled(vim.api.nvim_set_option_value)
  local open_win = core.marshaled(vim.api.nvim_open_win)
  local win_close = core.marshaled(vim.api.nvim_win_close)
  local set_config = core.marshaled(vim.api.nvim_win_set_config)

  -- Widest line by display width (so CJK / full-width text is not clipped).
  local function fit_width(lines)
    local w = 1
    for _, l in ipairs(lines) do
      local d = vim.fn.strdisplaywidth(l)
      if d > w then
        w = d
      end
    end
    return w
  end

  local M = {}

  ---@param content string|string[]
  ---@param opts? liv.std.popup.opts
  ---@return integer win
  function M.open(content, opts)
    opts = opts or {}
    local lines = text.lines(content)
    local buf = create_buf(false, true)
    set_lines(buf, 0, -1, false, lines)
    set_opt("bufhidden", "wipe", core.dict({ buf = buf }))
    local cfg = {
      relative = "editor",
      row = (opts.line or 1) - 1,
      col = (opts.col or 1) - 1,
      width = opts.width or fit_width(lines),
      height = opts.height or #lines,
      focusable = false, -- a display overlay, matching Vim popups
      style = "minimal",
    }
    if opts.border then
      cfg.border = opts.border == true and "single" or opts.border
      if opts.title then
        cfg.title = opts.title
      end
    end
    return open_win(buf, false, core.dict(cfg))
  end

  ---@param win integer
  function M.close(win)
    win_close(win, true)
  end

  ---@param win integer
  ---@param pos { line: integer, col: integer }
  function M.move(win, pos)
    set_config(
      win,
      core.dict({ relative = "editor", row = (pos.line or 1) - 1, col = (pos.col or 1) - 1 })
    )
  end

  ---@param win integer
  ---@param size { width: integer, height: integer }
  function M.resize(win, size)
    set_config(win, core.dict({ width = size.width, height = size.height }))
  end

  return M
end
