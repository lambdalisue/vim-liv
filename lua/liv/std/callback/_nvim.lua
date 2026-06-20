-- liv.std.callback Neovim backend: 'omnifunc'/'completefunc' accept a
-- `v:lua.<expr>` string on Neovim, so a forwarder function is not needed. We keep
-- the registered handlers in a liv-owned global table and return a `v:lua` path
-- into it. The wrapper marshals args in and the return out, matching the Vim
-- backend's contract (the handler always sees plain Lua values).
return function(core)
  local unpack = table.unpack or unpack
  -- A single global registry shared across any vendored liv copies, so the
  -- v:lua path resolves regardless of which copy created the handler. Keyed by a
  -- monotonically increasing id to avoid collisions.
  local REGISTRY = "__liv_callback"
  local registry = _G[REGISTRY]
  if not registry then
    registry = { _counter = 0 }
    _G[REGISTRY] = registry
  end

  local M = {}

  local PREFIX = "v:lua." .. REGISTRY .. "."

  ---@param handler fun(a: any, b: any): any
  ---@return string func_name
  function M.function_name(handler)
    registry._counter = registry._counter + 1
    local key = "cb" .. registry._counter
    registry[key] = function(a, b)
      return core.to_editor(handler(core.from_editor(a), core.from_editor(b)))
    end
    return PREFIX .. key
  end

  -- General form: bind a variadic handler reachable as a v:lua path. The wrapper
  -- marshals every incoming arg to plain Lua and the return back out, so a call
  -- of any arity (including zero) crosses the marshaling boundary correctly.
  ---@param handler fun(...): any
  ---@return string func_name
  function M.named(handler)
    registry._counter = registry._counter + 1
    local key = "cb" .. registry._counter
    registry[key] = function(...)
      local n = select("#", ...)
      local args = {}
      for i = 1, n do
        args[i] = core.from_editor((select(i, ...)))
      end
      return core.to_editor(handler(unpack(args, 1, n)))
    end
    return PREFIX .. key
  end

  -- Symmetric removal: drop the handler the name resolves to. Idempotent — a name
  -- already released (or never ours) is a no-op. The registry slot is cleared so
  -- the Lua closure can be collected.
  ---@param name string a value previously returned by function_name
  function M.release(name)
    if type(name) == "string" and name:sub(1, #PREFIX) == PREFIX then
      local key = name:sub(#PREFIX + 1)
      registry[key] = nil
    end
  end

  return M
end
