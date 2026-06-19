-- liv.std.callback Vim backend: route through the dispatch registry, which holds
-- the Lua handler alive and exposes a uniquely-named Vim forwarder (g:LivFunc{id})
-- bound to it. The forwarder name is what 'omnifunc'/'completefunc' is set to;
-- when the editor calls it as Func(findstart, base), the dispatch marshals the
-- args to plain Lua and the handler's return back to a Vim value.
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

  -- Symmetric removal: unregister the handler the name forwards to. Idempotent —
  -- a name already released (or never ours) is a no-op. The dispatch entry is
  -- dropped so the held Funcref is freed.
  ---@param name string a value previously returned by function_name
  function M.release(name)
    if ids[name] then
      dispatch.unregister(ids[name])
      ids[name] = nil
    end
  end

  return M
end
