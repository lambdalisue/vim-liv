-- liv.std._dispatch — Vim-side callback dispatch (internal to the _vim backends
-- of command/map/event). It sources the Vim 9 script companion (_dispatch.vim)
-- which holds Lua handlers as Funcrefs and invokes them from string-only rhs
-- contexts. Neovim does not use this -- its _nvim backends pass Lua callbacks to
-- the native API directly.
--
-- A factory: requires `core` so it can reach the editor and so tests could mock.
return function(core)
  local unpack = table.unpack or unpack
  -- Source the companion once (it guards against re-sourcing). The .vim sits
  -- beside this file; resolve its absolute path from this module's source.
  local here = debug.getinfo(1, "S").source:sub(2) -- strip the leading '@'
  local vimfile = here:gsub("%.lua$", ".vim")
  core.cmd("source " .. vimfile)

  local M = {}

  -- Register a Lua handler; returns its id (string). The handler is wrapped so
  -- that arguments arriving from Vim (e.g. an `<amatch>` string, or a context
  -- Dict built in the rhs) are marshaled to plain Lua before the handler sees
  -- them, and its return value is marshaled back for Vim (so an `<expr>` rhs
  -- gets a Vim string). This makes dispatch the symmetric inverse of
  -- `core.marshaled`: a Vim Dict reaches the handler as a plain table, never as
  -- userdata.
  ---@param handler function
  ---@return string id
  function M.register(handler)
    local wrapped = function(...)
      local n = select("#", ...)
      local args = {}
      for i = 1, n do
        args[i] = core.from_editor((select(i, ...)))
      end
      return core.to_editor(handler(unpack(args, 1, n)))
    end
    return core.call("LivRegister", wrapped)
  end

  -- Drop a handler by id.
  ---@param id string
  function M.unregister(id)
    core.call("LivUnregister", id)
  end

  -- Register a `customlist` completion handler and return the NAME of the Vim
  -- function to pass to `-complete=customlist,<name>`. The handler is registered
  -- like any other dispatch handler (so its (ArgLead, CmdLine, CursorPos) args
  -- are marshaled and its returned list is marshaled back); the companion builds
  -- a uniquely-named forwarder bound to that id.
  ---@param handler fun(arglead: string, cmdline: string, cursorpos: integer): string[]
  ---@return string id
  ---@return string complete_func the Vim function name for -complete=customlist
  function M.register_complete(handler)
    local id = M.register(handler)
    local name = core.call("LivCompleteRegister", id)
    return id, name
  end

  -- Register a two-argument handler and return the NAME of a Vim function that
  -- forwards to it. Built for string-valued options that name a function called
  -- as Func(a, b) — notably 'omnifunc'/'completefunc' (called Func(findstart,
  -- base)). The handler is registered like any other dispatch handler (its args
  -- are marshaled in and its return marshaled back), and the companion builds a
  -- uniquely-named forwarder bound to that id. The returned name is bare (no `g:`
  -- sigil) so it can be assigned to a buffer-local option directly.
  ---@param handler fun(a: any, b: any): any
  ---@return string id
  ---@return string func_name the Vim function name to assign to omnifunc/completefunc
  function M.register_function(handler)
    local id = M.register(handler)
    local name = core.call("LivFuncRegister", id)
    return id, name
  end

  -- The rhs fragment that invokes handler `id`, forwarding the given Vim
  -- argument expression(s) (e.g. "<q-args>").
  ---@param id string
  ---@param arg_expr string a Vim expression passed to the handler (may be "")
  ---@return string rhs
  function M.invoke_rhs(id, arg_expr)
    if arg_expr == nil or arg_expr == "" then
      return string.format("call g:LivInvoke('%s')", id)
    end
    return string.format("call g:LivInvoke('%s', %s)", id, arg_expr)
  end

  return M
end
