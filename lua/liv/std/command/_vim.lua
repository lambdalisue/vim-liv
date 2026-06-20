-- liv.std.command Vim backend: define a :command whose rhs calls the Lua handler
-- through the Vim 9 dispatch (the handler is held as a Funcref). <q-args> gives
-- the handler the same args string the Neovim backend passes.
return function(core)
  local dispatch = require("liv.std._dispatch")(core)
  local ids = {} -- name -> handler id, so remove/off can unregister
  local complete_ids = {} -- name -> completion handler id, unregistered on removal

  -- Drop the dispatch handler(s) previously registered for this command name, so
  -- a re-define or removal frees the prior Funcref(s) instead of leaking them.
  local function drop(name)
    if ids[name] then
      dispatch.unregister(ids[name])
      ids[name] = nil
    end
    if complete_ids[name] then
      dispatch.unregister(complete_ids[name])
      complete_ids[name] = nil
    end
  end

  local M = {}

  ---@param name string
  ---@param opts? { nargs?: string|integer, complete?: fun(arglead: string, cmdline: string, cursorpos: integer): string[] }
  ---@param handler fun(args: string)
  ---@return liv.std.command.sub
  function M.define(name, opts, handler)
    drop(name) -- re-defining the same command first frees the prior handler
    local id = dispatch.register(handler)
    ids[name] = id
    local complete_attr = ""
    if opts.complete then
      local cid, func = dispatch.register_complete(opts.complete)
      complete_ids[name] = cid
      complete_attr = "-complete=customlist," .. func .. " "
    end
    core.cmd(
      string.format(
        "command! -nargs=%s %s%s %s",
        tostring(opts.nargs or "*"),
        complete_attr,
        name,
        dispatch.invoke_rhs(id, "<q-args>")
      )
    )

    local removed = false
    return {
      -- Idempotent: a second off() (or off() after the command was deleted
      -- elsewhere) is a no-op. Deletes the command and unregisters its handlers.
      off = function()
        if removed then
          return
        end
        removed = true
        pcall(core.cmd, "delcommand " .. name)
        drop(name)
      end,
    }
  end

  ---@param name string
  function M.remove(name)
    core.cmd("delcommand " .. name)
    drop(name)
  end

  return M
end
