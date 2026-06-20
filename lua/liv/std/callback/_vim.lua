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

  -- General form: register the handler under a dispatch id (which marshals
  -- arbitrary args in and the return out) and bind a uniquely-named g: Funcref
  -- partial to g:LivInvoke with that id curried. Calling g:LivNamed{id}(...) thus
  -- routes to g:LivInvoke(id, ...), forwarding any arity — including zero — to the
  -- Lua handler. The returned name is callable as the head of a vimscript call
  -- expression (e.g. core.eval(name .. "(a, b)")).
  ---@param handler fun(...): any
  ---@return string func_name
  function M.named(handler)
    local id = dispatch.register(handler)
    local name = "g:LivNamed" .. id
    -- id is a numeric dispatch counter (digits only), so direct interpolation
    -- into the let-expression is injection-safe; no quoting helper needed.
    core.cmd(string.format("let %s = function('g:LivInvoke', ['%s'])", name, id))
    ids[name] = id
    return name
  end

  -- Symmetric removal: unregister the handler the name forwards to. Idempotent —
  -- a name already released (or never ours) is a no-op. The dispatch entry is
  -- dropped so the held Funcref is freed; for a named() binding the g: Funcref
  -- partial is also unlet so its slot does not linger.
  ---@param name string a value previously returned by function_name or named
  function M.release(name)
    if ids[name] then
      dispatch.unregister(ids[name])
      if name:sub(1, #"g:LivNamed") == "g:LivNamed" then
        core.cmd("unlet! " .. name)
      end
      ids[name] = nil
    end
  end

  return M
end
