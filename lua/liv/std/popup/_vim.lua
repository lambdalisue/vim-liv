-- liv.std.popup Vim backend: a popup window via popup_create. Several popup
-- options are pinned (fixed/flip/posinvert/scrollbar) so a popup behaves like a
-- Neovim float: a fixed-position overlay that never auto-repositions. Borders are
-- expressed as borderchars per style (the same glyphs Neovim draws). popup line/
-- col are already 1-based, matching liv's {line, col}.
local text = require("liv.lua.text")

return function(core)
  local fn = vim.fn
  local popup_create = core.marshaled(fn.popup_create)
  local popup_close = core.marshaled(fn.popup_close)
  local popup_move = core.marshaled(fn.popup_move)
  local popup_setoptions = core.marshaled(fn.popup_setoptions)

  -- Border glyphs in Vim's borderchars order: top, right, bottom, left,
  -- topleft, topright, botright, botleft.
  local BORDERCHARS = {
    single = { "─", "│", "─", "│", "┌", "┐", "┘", "└" },
    double = { "═", "║", "═", "║", "╔", "╗", "╝", "╚" },
    rounded = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
  }

  local M = {}

  ---@param content string|string[]
  ---@param opts? liv.std.popup.opts
  ---@return integer win
  function M.open(content, opts)
    opts = opts or {}
    local lines = text.lines(content)
    local o = {
      line = opts.line or 1,
      col = opts.col or 1,
      fixed = true, -- match Neovim: never auto-shift to stay on screen
      flip = false,
      posinvert = false,
      scrollbar = 0,
    }
    -- When width/height are omitted, the popup auto-fits its content (by display
    -- width), matching the Neovim backend's fit-to-content default.
    if opts.width then
      o.minwidth = opts.width
      o.maxwidth = opts.width
    end
    if opts.height then
      o.minheight = opts.height
      o.maxheight = opts.height
    end
    if opts.border then
      local style = opts.border == true and "single" or opts.border
      o.border = core.list({}) -- a border on every side
      o.borderchars = core.list(BORDERCHARS[style] or BORDERCHARS.single)
      if opts.title then
        o.title = opts.title
      end
    end
    return popup_create(lines, core.dict(o))
  end

  ---@param win integer
  function M.close(win)
    popup_close(win)
  end

  ---@param win integer
  ---@param pos { line: integer, col: integer }
  function M.move(win, pos)
    popup_move(win, core.dict({ line = pos.line or 1, col = pos.col or 1 }))
  end

  ---@param win integer
  ---@param size { width: integer, height: integer }
  function M.resize(win, size)
    popup_setoptions(
      win,
      core.dict({
        minwidth = size.width,
        maxwidth = size.width,
        minheight = size.height,
        maxheight = size.height,
      })
    )
  end

  return M
end
