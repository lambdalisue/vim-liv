-- liv.std.window Vim backend: bind Vim builtins as marshaled function references
-- (vim.fn.*) — the same shape the _nvim backend uses for vim.api.*, so marshaling
-- stays in core and is never hand-rolled. Vim cursor functions are 1-based for
-- both line and column, matching liv's {line, col} convention directly. A handle
-- of 0/nil resolves to the current window id once.
return function(core)
  local fn = vim.fn
  local win_getid = core.marshaled(fn.win_getid)
  local gettabinfo = core.marshaled(fn.gettabinfo)
  local tabpagenr = core.marshaled(fn.tabpagenr)
  local winbufnr = core.marshaled(fn.winbufnr)
  local win_gotoid = core.marshaled(fn.win_gotoid)
  local win_execute = core.marshaled(fn.win_execute)
  local winwidth = core.marshaled(fn.winwidth)
  local winheight = core.marshaled(fn.winheight)
  local line = core.marshaled(fn.line)
  local col = core.marshaled(fn.col)

  local M = {}

  local function winid(win)
    if win == nil or win == 0 then
      return win_getid()
    end
    return win
  end

  -- Resolve a handle AND assert it refers to a live window, so an invalid handle
  -- passed to an operation fails loudly (Vim's win_execute would silently no-op)
  -- with the same liv-branded error the Neovim backend raises. winbufnr returns
  -- -1 for a window id that no longer exists.
  local function valid_winid(win)
    local id = winid(win)
    if winbufnr(id) == -1 then
      error("liv.std.window: invalid window id: " .. tostring(win))
    end
    return id
  end

  ---Handle of the current window.
  ---@return integer
  function M.current()
    return win_getid()
  end

  ---Handles of all windows in the current tabpage.
  ---@return integer[]
  function M.all()
    -- windows of the current tabpage, in order
    local info = gettabinfo(tabpagenr())
    return info[1].windows
  end

  ---Buffer handle displayed in a window. winbufnr returns -1 for a window that
  ---no longer exists; raise there so an invalid handle fails the same way it
  ---does on Neovim (nvim_win_get_buf errors) instead of leaking -1.
  ---@param win integer? window handle; 0/nil = current
  ---@return integer
  function M.buffer(win)
    local b = winbufnr(winid(win))
    if b == -1 then
      error("liv.std.window.buffer: invalid window id: " .. tostring(win))
    end
    return b
  end

  ---Whether a window handle refers to a valid (existing) window.
  ---@param win integer? window handle; 0/nil = current
  ---@return boolean
  function M.valid(win)
    -- winbufnr returns -1 for a window id that no longer exists (tab-agnostic).
    return winbufnr(winid(win)) ~= -1
  end

  ---Focus (switch to) a window.
  ---@param win integer? window handle; 0/nil = current
  function M.focus(win)
    win_gotoid(valid_winid(win))
  end

  ---Close a window.
  ---@param win integer? window handle; 0/nil = current
  function M.close(win)
    win_execute(valid_winid(win), "close")
  end

  ---Size of a window as {width, height}.
  ---@param win integer? window handle; 0/nil = current
  ---@return integer[] # {width, height}
  function M.size(win)
    local w = valid_winid(win)
    return { winwidth(w), winheight(w) }
  end

  ---Cursor position of a window as {line, col}, both 1-based.
  ---@param win integer? window handle; 0/nil = current
  ---@return integer[] # {line, col}, both 1-based
  function M.cursor(win)
    local w = valid_winid(win)
    return { line(".", w), col(".", w) }
  end

  ---Move a window's cursor to pos = {line, col}, both 1-based.
  ---@param win integer? window handle; 0/nil = current
  ---@param pos integer[] {line, col}, both 1-based
  function M.set_cursor(win, pos)
    win_execute(valid_winid(win), "call cursor(" .. pos[1] .. ", " .. pos[2] .. ")")
  end

  return M
end
