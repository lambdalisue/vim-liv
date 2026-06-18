-- liv.std.tabpage Vim backend: bind Vim builtins as marshaled function references
-- (vim.fn.*) — the same shape the _nvim backend uses for vim.api.*, so marshaling
-- stays in core and is never hand-rolled. Vim identifies tabpages by their 1-based
-- number, which liv uses as the handle (0/nil = current).
return function(core)
  local fn = vim.fn
  local tabpagenr = core.marshaled(fn.tabpagenr)
  local gettabinfo = core.marshaled(fn.gettabinfo)

  local M = {}

  ---@return integer tab the current tabpage number
  function M.current()
    return tabpagenr()
  end

  ---@return integer[] tabs all tabpage numbers, in order
  function M.all()
    local last = tabpagenr("$")
    local tabs = {}
    for i = 1, last do
      tabs[i] = i
    end
    return tabs
  end

  ---@param tab integer? tabpage number (0/nil = current)
  ---@return integer[] wins the window ids in the tabpage
  function M.windows(tab)
    if tab == nil or tab == 0 then
      tab = tabpagenr()
    end
    -- gettabinfo returns [] for a tabpage that does not exist; raise a uniform
    -- liv error instead of indexing nil (which would leak an opaque Lua error,
    -- and differ from the Neovim backend's native failure).
    local info = gettabinfo(tab)
    if info[1] == nil then
      error("liv.std.tabpage: invalid tabpage id: " .. tostring(tab))
    end
    return info[1].windows
  end

  return M
end
