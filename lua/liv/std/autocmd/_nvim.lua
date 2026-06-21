-- liv.std.autocmd Neovim backend: native autocommands with a direct Lua callback
-- (no dispatch needed). Neovim hands the callback a rich info table; narrow it to
-- the liv context contract { buf, file, match }. trigger() fires a User event
-- without running modelines (matching the Vim backend).
return function(core)
  local create_au = core.marshaled(vim.api.nvim_create_autocmd)
  local del_au = core.marshaled(vim.api.nvim_del_autocmd)
  local exec_au = core.marshaled(vim.api.nvim_exec_autocmds)
  local create_augroup = core.marshaled(vim.api.nvim_create_augroup)
  local get_au = core.marshaled(vim.api.nvim_get_autocmds)
  local clear_au = core.marshaled(vim.api.nvim_clear_autocmds)

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

  ---Remove every autocommand in the named group (the group is shared on Neovim,
  ---so one native clear empties it). nvim_clear_autocmds raises if the group never
  ---existed; guard it so clearing an unknown/empty group is a no-op. The group
  ---persists (empty), so re-registering under it works.
  ---@param group string
  function M.clear(group)
    pcall(clear_au, core.dict({ group = group }))
  end

  ---@param opts? liv.std.autocmd.list.opts
  ---@return liv.std.autocmd.info[]
  function M.list(opts)
    opts = opts or {}
    -- Pass only `event` to the native query: filtering the group there errors when
    -- the group never existed (and the `_vim` backend's private-augroup suffix
    -- would not match the caller's group anyway), so group/pattern are filtered
    -- client-side for a uniform cross-editor contract.
    local query = {}
    if opts.event then
      query.event = opts.event
    end
    local out = {}
    for _, a in ipairs(get_au(core.dict(query))) do
      local group = a.group_name
      local group_ok = opts.group == nil
        or group == opts.group
        or (group ~= nil and group:sub(1, #opts.group + 1) == opts.group .. "_")
      local pattern_ok = opts.pattern == nil or a.pattern == opts.pattern
      if group_ok and pattern_ok then
        out[#out + 1] = {
          event = a.event,
          pattern = a.pattern,
          group = group,
          buffer = a.buffer or 0,
        }
      end
    end
    return out
  end

  return M
end
