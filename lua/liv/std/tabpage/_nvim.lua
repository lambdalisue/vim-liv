-- liv.std.tabpage Neovim backend: native API via core.marshaled. A tabpage
-- handle is an integer (0 = current).
return function(core)
  local current = core.marshaled(vim.api.nvim_get_current_tabpage)
  local list = core.marshaled(vim.api.nvim_list_tabpages)
  local tab_wins = core.marshaled(vim.api.nvim_tabpage_list_wins)

  local M = {}

  ---@return integer tab the current tabpage handle
  function M.current()
    return current()
  end

  ---@return integer[] tabs all tabpage handles
  function M.all()
    return list()
  end

  ---@param tab integer? tabpage handle (0/nil = current)
  ---@return integer[] wins the window handles in the tabpage
  function M.windows(tab)
    -- nvim_tabpage_list_wins raises a native error on an invalid handle; convert
    -- it to liv's uniform error so it reads the same as the Vim backend.
    local ok, wins = pcall(tab_wins, tab or 0)
    if not ok then
      error("liv.std.tabpage: invalid tabpage id: " .. tostring(tab))
    end
    return wins
  end

  return M
end
