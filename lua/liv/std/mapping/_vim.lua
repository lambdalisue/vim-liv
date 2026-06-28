-- liv.std.mapping Vim backend: build `:<mode>noremap` / `:<mode>map` commands. A
-- string rhs is used directly; a Lua-function rhs is registered with the Vim 9
-- dispatch and invoked with the liv context table. A normal mapping invokes the
-- handler from a `<Cmd>` rhs (which does not change mode); an `<expr>` mapping
-- evaluates `liv#std#dispatch#ExprInvoke(...)` so the handler's return string — with its
-- key-notation replaced by real termcodes — becomes the keys to type. The
-- <buffer>/<silent>/<nowait> modifiers mirror the opts.
local text = require("liv.lua.text.coerce")

return function(core)
  local dispatch = require("liv.std._dispatch")(core)
  local maparg = core.marshaled(vim.fn.maparg)
  local maplist = core.marshaled(vim.fn.maplist)
  local bufnr = core.marshaled(vim.fn.bufnr)
  local ids = {} -- map key -> handler id, so a re-map/del can unregister

  -- The `ids` key for a mapping. A buffer-local map is keyed per (mode, lhs,
  -- buffer): the SAME lhs mapped buffer-locally on two buffers must track two
  -- distinct handlers. Keying by (mode .. lhs) alone would make mapping it on
  -- buffer B `drop` (unregister) buffer A's still-live handler, leaving A's rhs
  -- calling a now-dead dispatch id (E716). A global map keeps the plain key.
  local function mapkey(mode, lhs, buffer)
    if buffer then
      return mode .. "\0" .. lhs .. "\0" .. bufnr("")
    end
    return mode .. lhs
  end

  -- Shape an editor maparg/maplist dict into the liv info table. A Lua-function
  -- rhs was set as a `<Cmd>call ...dispatch#Invoke(...)` / `...dispatch#ExprInvoke(...)`
  -- string (the Vim 9 dispatch), so it is reported as the marker "<Lua function>"
  -- — the internal dispatch string is not exposed. A genuine string rhs is verbatim.
  local function shape(d)
    local rhs = d.rhs or ""
    if rhs:find("dispatch#Invoke", 1, true) or rhs:find("dispatch#ExprInvoke", 1, true) then
      rhs = "<Lua function>"
    end
    return {
      lhs = d.lhs,
      rhs = rhs,
      mode = d.mode,
      noremap = d.noremap == 1,
      silent = d.silent == 1,
      expr = d.expr == 1,
      nowait = d.nowait == 1,
      buffer = d.buffer == 1,
    }
  end

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
    local keys = {} -- the ids keys this call created, for off()
    for _, mode in ipairs(text.aslist(modes)) do
      local key = mapkey(mode, lhs, opts.buffer)
      drop(key) -- re-mapping the same key first frees the prior handler
      local rhs_str
      if type(rhs) == "function" then
        local id = dispatch.register(rhs)
        ids[key] = id
        -- `mode` is the declared mode for this mapping: deterministic and
        -- identical to the Neovim backend (mode() under <Cmd> reports "c" here).
        local ctx = string.format("{'count': v:count, 'register': v:register, 'mode': '%s'}", mode)
        if opts.expr then
          rhs_str = string.format("liv#std#dispatch#ExprInvoke('%s', %s)", id, ctx)
        else
          rhs_str = string.format("<Cmd>call liv#std#dispatch#Invoke('%s', %s)<CR>", id, ctx)
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
      -- Compute the ids key BEFORE the unmap (a buffer-local key reads the current
      -- buffer, which the unmap does not change, but order it defensively).
      local key = mapkey(mode, lhs, opts.buffer)
      core.cmd(mode .. "unmap " .. buffer .. lhs)
      drop(key)
    end
  end

  ---@param modes string|string[]
  ---@param lhs string
  ---@param opts? { buffer?: boolean }
  ---@return liv.std.mapping.info?
  function M.get(modes, lhs, opts)
    opts = opts or {}
    -- A mapping is queried one mode at a time; take the first when a list is given.
    local mode = text.aslist(modes)[1]
    -- maparg(lhs, mode, abbr=false, dict=true) yields the rich dict; an absent
    -- mapping yields an empty dict (next() == nil).
    local d = maparg(lhs, mode, false, true)
    if type(d) ~= "table" or next(d) == nil then
      return nil
    end
    -- Honor opts.buffer: maparg reports buffer-locality via the `buffer` field
    -- (1 = buffer-local to the current buffer). A buffer-local query returns the
    -- mapping only when it is actually buffer-local; a global query rejects a
    -- buffer-local shadow (maparg has no global-only mode, so a shadowed global
    -- reads as absent — documented limitation).
    local is_local = d.buffer == 1
    if (opts.buffer and not is_local) or (not opts.buffer and is_local) then
      return nil
    end
    return shape(d)
  end

  ---@param opts? liv.std.mapping.list.opts
  ---@return liv.std.mapping.info[]
  function M.list(opts)
    opts = opts or {}
    local out = {}
    for _, d in ipairs(maplist()) do
      local lhs = d.lhs or ""
      local mode_ok = opts.mode == nil or d.mode == opts.mode
      local prefix_ok = opts.prefix == nil or lhs:sub(1, #opts.prefix) == opts.prefix
      if mode_ok and prefix_ok then
        out[#out + 1] = shape(d)
      end
    end
    return out
  end

  return M
end
