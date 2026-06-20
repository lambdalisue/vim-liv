-- liv.std.popup Neovim backend: the caller's buffer shown in a non-focusable
-- floating window (buffer-backed: nvim_open_win binds the caller's bufnr, so
-- writes to the buffer update the popup live). enter=false + focusable=false
-- keeps it a non-interactive overlay (Vim popup parity). The buffer is the
-- caller's — closing the window never wipes it. liv's 1-based {line, col} maps to
-- Neovim's 0-based row/col; omitting width/height fits the float to the buffer.
return function(core)
  local get_lines = core.marshaled(vim.api.nvim_buf_get_lines)
  local open_win = core.marshaled(vim.api.nvim_open_win)
  local win_close = core.marshaled(vim.api.nvim_win_close)
  local set_config = core.marshaled(vim.api.nvim_win_set_config)
  local set_win_option = core.marshaled(vim.api.nvim_set_option_value)

  -- Map liv's { normal, border } to a 'winhighlight' remap. The float's background
  -- (NormalFloat) defaults to "Normal" so it reads as an ordinary window (parity
  -- with the Vim backend's default); the border (FloatBorder) is remapped only when
  -- given, otherwise the editor's FloatBorder default stands.
  local function winhighlight(opts)
    local normal = (opts.highlight and opts.highlight.normal) or "Normal"
    local wh = "NormalFloat:" .. normal
    if opts.highlight and opts.highlight.border then
      wh = wh .. ",FloatBorder:" .. opts.highlight.border
    end
    return wh
  end

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

  -- Resolve width/height, fitting to the buffer's content when either is omitted
  -- (nvim_open_win requires both; Vim auto-fits, so this keeps the two in parity).
  local function size(bufnr, opts)
    local width, height = opts.width, opts.height
    if not width or not height then
      local lines = get_lines(bufnr, 0, -1, false)
      width = width or fit_width(lines)
      height = height or math.max(1, #lines)
    end
    return width, height
  end

  local M = {}

  ---@param bufnr integer caller-owned buffer to display
  ---@param opts? liv.std.popup.opts
  ---@return integer win
  function M.open(bufnr, opts)
    opts = opts or {}
    local width, height = size(bufnr, opts)
    local cfg = {
      relative = opts.relative or "editor", -- "editor" | "cursor"
      row = (opts.line or 1) - 1,
      col = (opts.col or 1) - 1,
      width = width,
      height = height,
      focusable = false, -- a display overlay, matching Vim popups
      style = "minimal",
    }
    if opts.anchor then
      cfg.anchor = opts.anchor -- "NW" | "NE" | "SW" | "SE"
    end
    if opts.zindex then
      cfg.zindex = opts.zindex
    end
    if opts.border then
      cfg.border = opts.border == true and "single" or opts.border
      if opts.title then
        cfg.title = opts.title
      end
    end
    local win = open_win(bufnr, false, core.dict(cfg))
    set_win_option("winhighlight", winhighlight(opts), core.dict({ win = win }))
    return win
  end

  ---@param win integer
  function M.close(win)
    win_close(win, true)
  end

  ---Reconfigure an open popup in place (title / size / position). 1-based.
  ---@param win integer
  ---@param opts liv.std.popup.opts
  function M.config(win, opts)
    local cfg = {}
    -- Repositioning requires `relative`; set it (with the optional anchor) only when
    -- a position is given so a size-only reconfigure leaves the float where it is.
    if opts.line or opts.col then
      cfg.relative = opts.relative or "editor"
      cfg.row = (opts.line or 1) - 1
      cfg.col = (opts.col or 1) - 1
      if opts.anchor then
        cfg.anchor = opts.anchor
      end
    end
    if opts.width then
      cfg.width = opts.width
    end
    if opts.height then
      cfg.height = opts.height
    end
    if opts.zindex then
      cfg.zindex = opts.zindex
    end
    if opts.border then
      cfg.border = opts.border == true and "single" or opts.border
    end
    if opts.title then
      cfg.title = opts.title
    end
    set_config(win, core.dict(cfg))
    -- A highlight change is a window option, not part of the config dict.
    if opts.highlight then
      set_win_option("winhighlight", winhighlight(opts), core.dict({ win = win }))
    end
  end

  ---@param win integer
  ---@param pos { line: integer, col: integer }
  function M.move(win, pos)
    M.config(win, { line = pos.line or 1, col = pos.col or 1 })
  end

  ---@param win integer
  ---@param dims { width: integer, height: integer }
  function M.resize(win, dims)
    M.config(win, { width = dims.width, height = dims.height })
  end

  return M
end
