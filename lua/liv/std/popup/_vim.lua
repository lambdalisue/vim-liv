-- liv.std.popup Vim backend: a popup window via popup_create, bound to the
-- caller's buffer (buffer-backed: popup_create takes a bufnr, so writes to the
-- buffer update the popup live). Several popup options are pinned (fixed/flip/
-- posinvert/scrollbar) so a popup behaves like a Neovim float: a fixed-position
-- overlay that never auto-repositions. Borders are expressed as borderchars per
-- style (the same glyphs Neovim draws). popup line/col are already 1-based,
-- matching liv's {line, col}; omitting width/height lets the popup fit the buffer.
--
-- The configurable surface mirrors denops/std's popup (relative / anchor / width /
-- height / line,col / zindex / border / title / highlight). The only deliberate
-- default deviation: the popup background highlight defaults to "Normal" (Vim's
-- popup default is the pink Pmenu), while the border highlight is left to the
-- editor default unless given (denops imposes no Normal default either).
return function(core)
  local fn = vim.fn
  local popup_create = core.marshaled(fn.popup_create)
  local popup_close = core.marshaled(fn.popup_close)
  local popup_setoptions = core.marshaled(fn.popup_setoptions)

  -- Border glyphs in Vim's borderchars order: top, right, bottom, left,
  -- topleft, topright, botright, botleft.
  local BORDERCHARS = {
    single = { "─", "│", "─", "│", "┌", "┐", "┘", "└" },
    double = { "═", "║", "═", "║", "╔", "╗", "╝", "╚" },
    rounded = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
  }

  -- liv anchor -> Vim popup `pos` (which corner sits at {line, col}).
  local POS = { NW = "topleft", NE = "topright", SW = "botleft", SE = "botright" }

  -- A cursor-relative line/col: liv's 1-based offset (1 = at the cursor) maps to
  -- Vim's "cursor" / "cursor+N" / "cursor-N" position strings.
  local function cursor_rel(n)
    local off = (n or 1) - 1
    if off == 0 then
      return "cursor"
    elseif off > 0 then
      return "cursor+" .. off
    end
    return "cursor" .. off -- e.g. "cursor-1"
  end

  -- Position (line/col, relative-aware) + anchor onto an options dict.
  local function with_position(o, opts)
    if opts.anchor then
      o.pos = POS[opts.anchor]
    end
    if opts.relative == "cursor" then
      o.line = cursor_rel(opts.line)
      o.col = cursor_rel(opts.col)
    else
      if opts.line then
        o.line = opts.line
      end
      if opts.col then
        o.col = opts.col
      end
    end
  end

  -- A fixed width/height pins both min and max so the popup neither grows nor
  -- shrinks to its content.
  local function with_size(o, opts)
    if opts.width then
      o.minwidth, o.maxwidth = opts.width, opts.width
    end
    if opts.height then
      o.minheight, o.maxheight = opts.height, opts.height
    end
  end

  -- Border/title onto an options dict.
  local function with_border(o, opts)
    if opts.border then
      local style = opts.border == true and "single" or opts.border
      o.border = core.list({}) -- a border on every side
      o.borderchars = core.list(BORDERCHARS[style] or BORDERCHARS.single)
      if opts.title then
        o.title = opts.title
      end
    end
  end

  -- Highlight (normal/border) + zindex. `give_normal_default` applies the "Normal"
  -- background default (only on open; a geometry-only config must not reset it).
  local function with_appearance(o, opts, give_normal_default)
    if opts.highlight and opts.highlight.normal then
      o.highlight = opts.highlight.normal
    elseif give_normal_default then
      o.highlight = "Normal"
    end
    if opts.highlight and opts.highlight.border then
      o.borderhighlight = core.list({ opts.highlight.border })
    end
    if opts.zindex then
      o.zindex = opts.zindex
    end
  end

  local M = {}

  ---@param bufnr integer caller-owned buffer to display
  ---@param opts? liv.std.popup.opts
  ---@return integer win
  function M.open(bufnr, opts)
    opts = opts or {}
    local o = {
      line = opts.line or 1,
      col = opts.col or 1,
      fixed = true, -- match Neovim: never auto-shift to stay on screen
      flip = false,
      posinvert = false,
      scrollbar = 0,
    }
    with_position(o, opts)
    with_size(o, opts)
    with_border(o, opts)
    with_appearance(o, opts, true)
    return popup_create(bufnr, core.dict(o))
  end

  ---@param win integer
  function M.close(win)
    popup_close(win)
  end

  ---Reconfigure an open popup in place (position / size / border / appearance). 1-based.
  ---@param win integer
  ---@param opts liv.std.popup.opts
  function M.config(win, opts)
    local o = {}
    with_position(o, opts)
    with_size(o, opts)
    with_border(o, opts)
    with_appearance(o, opts, false)
    popup_setoptions(win, core.dict(o))
  end

  ---@param win integer
  ---@param pos { line: integer, col: integer }
  function M.move(win, pos)
    M.config(win, { line = pos.line or 1, col = pos.col or 1 })
  end

  ---@param win integer
  ---@param size { width: integer, height: integer }
  function M.resize(win, size)
    M.config(win, { width = size.width, height = size.height })
  end

  return M
end
