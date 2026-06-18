-- liv.std.autocmd Neovim backend: native autocommands with a direct Lua callback
-- (no dispatch needed). Neovim hands the callback a rich info table; narrow it to
-- the liv context contract { buf, file, match }. trigger() fires a User event
-- without running modelines (matching the Vim backend).
return function(core)
  local create_au = core.marshaled(vim.api.nvim_create_autocmd)
  local del_au = core.marshaled(vim.api.nvim_del_autocmd)
  local exec_au = core.marshaled(vim.api.nvim_exec_autocmds)
  local create_augroup = core.marshaled(vim.api.nvim_create_augroup)

  local M = {}

  ---@param events string|string[]
  ---@param opts? liv.std.autocmd.opts
  ---@param handler fun(ctx: liv.std.autocmd.ctx)
  ---@return liv.std.autocmd.sub
  function M.on(events, opts, handler)
    local o = {
      callback = function(info)
        handler({ buf = info.buf, file = info.file, match = info.match })
      end,
    }
    if opts.buffer then
      o.buffer = opts.buffer
    elseif opts.pattern then
      o.pattern = opts.pattern
    end
    if opts.group then
      -- Neovim requires the group to exist before it can be named on an
      -- autocommand; ensure it (clear=false so a re-used group keeps its prior
      -- autocommands, matching the Vim backend, where naming a group just adds).
      create_augroup(opts.group, core.dict({ clear = false }))
      o.group = opts.group
    end
    if opts.once then
      o.once = true
    end
    local id = create_au(events, core.dict(o))
    local removed = false
    return {
      -- Idempotent: a `once` autocommand deletes itself after firing, so the id
      -- may already be gone by the time off() runs; the flag also makes a second
      -- off() a no-op.
      off = function()
        if removed then
          return
        end
        removed = true
        pcall(del_au, id)
      end,
    }
  end

  ---@param name string the User event name to fire
  function M.trigger(name)
    exec_au("User", core.dict({ pattern = name, modeline = false }))
  end

  return M
end
