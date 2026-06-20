-- liv.std.variable Neovim backend: native nvim_*_var via core.marshaled (clean
-- getters/setters per scope; 0 means the current buffer/window/tabpage).
-- A missing variable returns nil: the native getters raise on an absent key, so
-- each getter pcalls and maps the failure to nil (the scope handle is always
-- current, so the only failure mode is the missing key, never a bad handle).
return function(core)
  local M = { get = {}, set = {} }

  local g_get = core.marshaled(vim.api.nvim_get_var)
  local g_set = core.marshaled(vim.api.nvim_set_var)
  local b_get = core.marshaled(vim.api.nvim_buf_get_var)
  local b_set = core.marshaled(vim.api.nvim_buf_set_var)
  local w_get = core.marshaled(vim.api.nvim_win_get_var)
  local w_set = core.marshaled(vim.api.nvim_win_set_var)
  local t_get = core.marshaled(vim.api.nvim_tabpage_get_var)
  local t_set = core.marshaled(vim.api.nvim_tabpage_set_var)
  local v_get = core.marshaled(vim.api.nvim_get_vvar)
  local v_set = core.marshaled(vim.api.nvim_set_vvar)
  -- Registers: no native nvim_* register API differs observably from getreg/
  -- setreg, so route through the vimscript builtins (same shape as the _vim
  -- backend). getreg returns "" for an empty register -- a register is a slot
  -- that always exists, never "undefined", so there is no nil to map here.
  local r_get = core.marshaled(vim.fn.getreg)
  local r_set = core.marshaled(vim.fn.setreg)

  -- Absent variable -> nil (not an error). Only the missing-key failure can occur
  -- here since the scope handle is always current.
  local function missing_nil(getter, ...)
    local ok, value = pcall(getter, ...)
    if not ok then
      return nil
    end
    return value
  end

  ---@param name string
  ---@return any
  M.get.global = function(name)
    return missing_nil(g_get, name)
  end
  ---@param name string
  ---@return any
  M.get.buffer = function(name)
    return missing_nil(b_get, 0, name)
  end
  ---@param name string
  ---@return any
  M.get.window = function(name)
    return missing_nil(w_get, 0, name)
  end
  ---@param name string
  ---@return any
  M.get.tab = function(name)
    return missing_nil(t_get, 0, name)
  end
  ---@param name string
  ---@return any
  M.get.vim = function(name)
    return missing_nil(v_get, name)
  end

  ---@param name string
  ---@param value any
  M.set.global = function(name, value)
    g_set(name, value)
  end
  ---@param name string
  ---@param value any
  M.set.buffer = function(name, value)
    b_set(0, name, value)
  end
  ---@param name string
  ---@param value any
  M.set.window = function(name, value)
    w_set(0, name, value)
  end
  ---@param name string
  ---@param value any
  M.set.tab = function(name, value)
    t_set(0, name, value)
  end
  -- Setting a read-only v: var raises (an operation failure), which is acceptable.
  ---@param name string
  ---@param value any
  M.set.vim = function(name, value)
    v_set(name, value)
  end

  -- Registers always exist as slots, so getreg yields "" (not nil) for an empty
  -- one -- the missing-value here is "", unlike the nil-for-undefined scopes.
  ---@param name string
  ---@return string
  M.get.register = function(name)
    return r_get(name)
  end
  ---@param name string
  ---@param value string
  M.set.register = function(name, value)
    r_set(name, value)
  end

  -- Environment: vim.uv.os_getenv/os_setenv are the native libuv calls and the
  -- correct path on Neovim -- they speak plain Lua values (no marshaling, no NIL
  -- sentinel) and distinguish unset (nil) from set-empty (""). Call them
  -- directly, NOT through core.marshaled, since they are not vimscript.
  ---@param name string
  ---@return string|nil
  M.get.env = function(name)
    return vim.uv.os_getenv(name)
  end
  ---@param name string
  ---@param value string
  M.set.env = function(name, value)
    vim.uv.os_setenv(name, value)
  end

  return M
end
