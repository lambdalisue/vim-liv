-- liv.std.task Neovim leaves: the editor-dependent primitives injected into the
-- pure liv.lua.async engine. schedule resumes on the main loop; timer is a
-- one-shot libuv timer returning a canceler; wait synchronously pumps the loop.
return function(_core)
  local M = {}

  ---@param fn fun()
  function M.schedule(fn)
    vim.schedule(fn)
  end

  ---@param ms integer
  ---@param fn fun()
  ---@return fun() canceler
  function M.timer(ms, fn)
    local t = vim.uv.new_timer()
    t:start(ms, 0, function()
      t:stop()
      t:close()
      fn()
    end)
    return function()
      if not t:is_closing() then
        t:stop()
        t:close()
      end
    end
  end

  -- Pump the event loop until cond() or ms elapses; returns whether cond() held.
  ---@param ms integer
  ---@param cond fun(): boolean
  ---@return boolean
  function M.wait(ms, cond)
    return vim.wait(ms, cond, 10) == true
  end

  return M
end
