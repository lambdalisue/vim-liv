-- liv.std.callback Vim backend: route through the dispatch registry, which holds
-- the Lua handler alive and exposes a uniquely-named Vim forwarder bound to it.
-- The forwarder name is what 'omnifunc'/'completefunc' is set to; when the editor
-- calls it as Func(findstart, base), the dispatch marshals the args to plain Lua
-- and the handler's return back to a Vim value. The companion mints the forwarder
-- names (uniquely prefixed per bundle), so they are opaque to this module.
return function(core)
  local dispatch = require("liv.std._dispatch")(core)

  local ids = {} -- forwarder name -> dispatch id, so release can unregister it

  local M = {}

  ---@param handler fun(a: any, b: any): any
  ---@return string func_name
  function M.function_name(handler)
    local id, name = dispatch.register_function(handler)
    ids[name] = id
    return name
  end

  -- General form: register the handler under a dispatch id (which marshals
  -- arbitrary args in and the return out); the companion binds a uniquely-named
  -- g: Funcref partial to its Invoke with that id curried and returns the
  -- (g:-qualified) name. Calling that name(...) forwards to Invoke(id, ...) for
  -- any arity — including zero. The returned name is callable as the head of a
  -- vimscript call expression (e.g. core.eval(name .. "(a, b)")).
  ---@param handler fun(...): any
  ---@return string func_name
  function M.named(handler)
    local id = dispatch.register(handler)
    local name = core.call("liv#std#dispatch#NamedRegister", id)
    ids[name] = id
    return name
  end

  -- Symmetric removal: unregister the handler the name forwards to. Idempotent —
  -- a name already released (or never ours) is a no-op. The dispatch entry is
  -- dropped so the held Funcref is freed; a named() binding is a g: Funcref
  -- variable, so its slot is also unlet (function_name() forwarders are bare-named
  -- global functions reused by id and are intentionally left in place).
  ---@param name string a value previously returned by function_name or named
  function M.release(name)
    if ids[name] then
      dispatch.unregister(ids[name])
      if name:sub(1, 2) == "g:" then
        core.cmd("unlet! " .. name)
      end
      ids[name] = nil
    end
  end

  return M
end
