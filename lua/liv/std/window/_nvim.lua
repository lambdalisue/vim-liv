-- liv.std.window Neovim backend: native API via core.marshaled. Neovim cursor
-- is {row (1-based), col (0-based)}; liv positions are {line, col} both 1-based,
-- so the column is shifted by one across the boundary.

-- Build the Ex command that opens a split relative to the current window.
-- `above`/`left` open before it, `below`/`right` after; `left`/`right` are
-- vertical (so `size` is a width), `above`/`below` horizontal (a height). Default
-- direction is `below`. Identical on both editors (plain :split modifiers).
local function split_cmd(opts)
  local dir = opts.split or "below"
  local pos = (dir == "above" or dir == "left") and "aboveleft" or "belowright"
  local vertical = (dir == "left" or dir == "right") and "vertical " or ""
  local size = opts.size and tostring(opts.size) or ""
  return pos .. " " .. vertical .. size .. "split"
end

return function(core)
  local current = core.marshaled(vim.api.nvim_get_current_win)
  local win_buf = core.marshaled(vim.api.nvim_win_get_buf)
  local win_is_valid = core.marshaled(vim.api.nvim_win_is_valid)
  local get_cursor = core.marshaled(vim.api.nvim_win_get_cursor)
  local set_cursor = core.marshaled(vim.api.nvim_win_set_cursor)
  local tab_wins = core.marshaled(vim.api.nvim_tabpage_list_wins)
  local set_current = core.marshaled(vim.api.nvim_set_current_win)
  local win_close = core.marshaled(vim.api.nvim_win_close)
  local win_width = core.marshaled(vim.api.nvim_win_get_width)
  local win_height = core.marshaled(vim.api.nvim_win_get_height)
  local set_buf = core.marshaled(vim.api.nvim_win_set_buf)

  local M = {}

  -- Resolve a handle AND assert it refers to a live window, so an invalid handle
  -- passed to an operation raises the same liv-branded error as the Vim backend
  -- (instead of nvim_*'s native message). 0/nil is the current window, always live.
  local function valid_win(win)
    win = win or 0
    if win ~= 0 and not win_is_valid(win) then
      error("liv.std.window: invalid window id: " .. tostring(win))
    end
    return win
  end

  ---Handle of the current window.
  ---@return integer
  function M.current()
    return current()
  end

  ---Handles of all windows in the current tabpage.
  ---@return integer[]
  function M.all()
    return tab_wins(0) -- windows of the current tabpage
  end

  ---Buffer handle displayed in a window. Raises on an invalid window handle.
  ---nvim_win_get_buf raises its own native message; convert it to liv's so the
  ---error reads the same on both editors (the Vim backend raises the same text).
  ---@param win integer? window handle; 0/nil = current
  ---@return integer
  function M.buffer(win)
    local ok, buf = pcall(win_buf, win or 0)
    if not ok then
      error("liv.std.window.buffer: invalid window id: " .. tostring(win))
    end
    return buf
  end

  ---Whether a window handle refers to a valid (existing) window.
  ---@param win integer? window handle; 0/nil = current
  ---@return boolean
  function M.valid(win)
    if win == nil or win == 0 then
      return true
    end
    return win_is_valid(win)
  end

  ---Focus (switch to) a window.
  ---@param win integer? window handle; 0/nil = current
  function M.focus(win)
    set_current(valid_win(win))
  end

  ---Close a window.
  ---@param win integer? window handle; 0/nil = current
  function M.close(win)
    win_close(valid_win(win), false)
  end

  ---Size of a window as {width, height}.
  ---@param win integer? window handle; 0/nil = current
  ---@return integer[] # {width, height}
  function M.size(win)
    win = valid_win(win)
    return { win_width(win), win_height(win) }
  end

  ---Cursor position of a window as {line, col}, both 1-based.
  ---@param win integer? window handle; 0/nil = current
  ---@return integer[] # {line, col}, both 1-based
  function M.cursor(win)
    local pos = get_cursor(valid_win(win))
    return { pos[1], pos[2] + 1 }
  end

  ---Move a window's cursor to pos = {line, col}, both 1-based.
  ---@param win integer? window handle; 0/nil = current
  ---@param pos integer[] {line, col}, both 1-based
  function M.set_cursor(win, pos)
    set_cursor(valid_win(win), { pos[1], pos[2] - 1 })
  end

  ---Open the caller-owned buffer `bufnr` in a NEW split window and return its
  ---handle. The split is relative to the current window: `above`/`below` are
  ---horizontal (a height in cells via `size`), `left`/`right` are vertical (a
  ---width). The new window is focused unless `focus = false`, which leaves the
  ---current window focused. The buffer is the caller's — closing the window never
  ---wipes it. (Float overlay? Use liv.std.popup instead.)
  ---@param bufnr integer buffer to display (caller-owned)
  ---@param opts? { split?: "above"|"below"|"left"|"right", size?: integer, focus?: boolean }
  ---@return integer win
  function M.open(bufnr, opts)
    opts = opts or {}
    local origin = current()
    core.cmd(split_cmd(opts) .. " | buffer " .. bufnr)
    local win = current()
    if opts.focus == false then
      set_current(origin)
    end
    return win
  end

  ---Display the caller-owned buffer `bufnr` in window `win` (swap its buffer).
  ---@param win integer? window handle; 0/nil = current
  ---@param bufnr integer buffer to display (caller-owned)
  function M.set_buffer(win, bufnr)
    set_buf(valid_win(win), bufnr)
  end

  return M
end
