-- liv.std.command Neovim backend: native nvim_create_user_command with a direct
-- Lua callback (no dispatch needed). Neovim passes the callback a table; unify to
-- the liv contract handler(args: string).
return function(core)
  local create = core.marshaled(vim.api.nvim_create_user_command)
  local del = core.marshaled(vim.api.nvim_del_user_command)

  local M = {}

  ---@param name string
  ---@param opts? { nargs?: string|integer, complete?: fun(arglead: string, cmdline: string, cursorpos: integer): string[] }
  ---@param handler fun(args: string)
  ---@return liv.std.command.sub
  function M.define(name, opts, handler)
    -- Neovim wants nargs as 0/1 (numbers) or "*"/"?"/"+"; accept "0"/"1" too.
    local nargs = opts.nargs or "*"
    if nargs == "0" then
      nargs = 0
    elseif nargs == "1" then
      nargs = 1
    end
    local cmd_opts = { nargs = nargs }
    if opts.complete then
      local completer = opts.complete
      -- Native custom completion: a Lua function returning the candidate list.
      cmd_opts.complete = function(arglead, cmdline, cursorpos)
        return completer(arglead, cmdline, cursorpos) or {}
      end
    end
    create(name, function(info)
      return handler(info.args)
    end, core.dict(cmd_opts))

    local removed = false
    return {
      -- Idempotent: a second off() (or off() after an external delete) is a no-op.
      off = function()
        if removed then
          return
        end
        removed = true
        pcall(del, name)
      end,
    }
  end

  ---@param name string
  function M.remove(name)
    del(name)
  end

  return M
end
