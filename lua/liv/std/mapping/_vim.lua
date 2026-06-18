-- liv.std.mapping Vim backend: build `:<mode>noremap` / `:<mode>map` commands. A
-- string rhs is used directly; a Lua-function rhs is registered with the Vim 9
-- dispatch and invoked with the liv context table. A normal mapping invokes the
-- handler from a `<Cmd>` rhs (which does not change mode); an `<expr>` mapping
-- evaluates `g:LivExprInvoke(...)` so the handler's return string — with its
-- key-notation replaced by real termcodes — becomes the keys to type. The
-- <buffer>/<silent>/<nowait> modifiers mirror the opts.
local text = require("liv.lua.text")

return function(core)
  local dispatch = require("liv.std._dispatch")(core)
  local ids = {} -- (mode .. lhs) -> handler id, so a re-map/del can unregister

  -- Drop the dispatch handler previously registered for this key (if any), so a
  -- re-register or removal frees the prior Funcref instead of leaking it.
  local function drop(key)
    if ids[key] then
      dispatch.unregister(ids[key])
      ids[key] = nil
    end
  end

  local M = {}

  ---@param modes string|string[]
  ---@param lhs string
  ---@param opts? liv.std.mapping.opts
  ---@param rhs string|fun(ctx: liv.std.mapping.ctx): string?
  function M.set(modes, lhs, opts, rhs)
    local keys = {} -- the (mode .. lhs) keys this call created, for off()
    for _, mode in ipairs(text.aslist(modes)) do
      local key = mode .. lhs
      drop(key) -- re-mapping the same key first frees the prior handler
      local rhs_str
      if type(rhs) == "function" then
        local id = dispatch.register(rhs)
        ids[key] = id
        -- `mode` is the declared mode for this mapping: deterministic and
        -- identical to the Neovim backend (mode() under <Cmd> reports "c" here).
        local ctx = string.format("{'count': v:count, 'register': v:register, 'mode': '%s'}", mode)
        if opts.expr then
          rhs_str = string.format("g:LivExprInvoke('%s', %s)", id, ctx)
        else
          rhs_str = string.format("<Cmd>call g:LivInvoke('%s', %s)<CR>", id, ctx)
        end
      else
        rhs_str = rhs
      end
      local parts = { mode .. (opts.noremap ~= false and "noremap" or "map") }
      if opts.buffer then
        parts[#parts + 1] = "<buffer>"
      end
      if opts.expr then
        parts[#parts + 1] = "<expr>"
      end
      if opts.silent then
        parts[#parts + 1] = "<silent>"
      end
      if opts.nowait then
        parts[#parts + 1] = "<nowait>"
      end
      parts[#parts + 1] = lhs
      parts[#parts + 1] = rhs_str
      core.cmd(table.concat(parts, " "))
      keys[#keys + 1] = { mode = mode, key = key }
    end

    local removed = false
    return {
      -- Idempotent: a second off() (or off() after the mapping was deleted
      -- elsewhere) is a no-op. Removes the mapping for every mode this call
      -- created and unregisters each dispatch handler so no Funcref leaks.
      off = function()
        if removed then
          return
        end
        removed = true
        local buffer = opts.buffer and "<buffer> " or ""
        for _, entry in ipairs(keys) do
          pcall(core.cmd, entry.mode .. "unmap " .. buffer .. lhs)
          drop(entry.key)
        end
      end,
    }
  end

  ---@param modes string|string[]
  ---@param lhs string
  ---@param opts? { buffer?: boolean }
  function M.del(modes, lhs, opts)
    opts = opts or {}
    for _, mode in ipairs(text.aslist(modes)) do
      local buffer = opts.buffer and "<buffer> " or ""
      core.cmd(mode .. "unmap " .. buffer .. lhs)
      drop(mode .. lhs)
    end
  end

  return M
end
