-- liv.std.mapping Neovim backend: native nvim_set_keymap / nvim_buf_set_keymap. A
-- Lua-function rhs is passed as opts.callback (with an empty string rhs) and
-- wrapped to receive the liv context table; a string rhs is used as-is. For an
-- expr mapping the callback's return string is used as the keys (replace_keycodes
-- so `<...>` notation works).
local text = require("liv.lua.text.coerce")

return function(core)
  local set_keymap = core.marshaled(vim.api.nvim_set_keymap)
  local del_keymap = core.marshaled(vim.api.nvim_del_keymap)
  local set_buf_keymap = core.marshaled(vim.api.nvim_buf_set_keymap)
  local del_buf_keymap = core.marshaled(vim.api.nvim_buf_del_keymap)
  -- maparg (dict form) and maplist work identically on both editors, so the
  -- info-shaping is shared with the Vim backend in spirit; each backend binds its
  -- own native references so marshaling stays in core.
  local maparg = core.marshaled(vim.fn.maparg)
  local maplist = core.marshaled(vim.fn.maplist)

  -- Shape an editor maparg/maplist dict into the liv info table. A Lua-function
  -- rhs is reported as the marker "<Lua function>": Neovim flags it with a
  -- `callback` field in the dict.
  local function shape(d)
    local rhs = d.rhs or ""
    if d.callback ~= nil then
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

  local M = {}

  ---@param modes string|string[]
  ---@param lhs string
  ---@param opts? liv.std.mapping.opts
  ---@param rhs string|fun(ctx: liv.std.mapping.ctx): string?
  function M.set(modes, lhs, opts, rhs)
    local created = {} -- modes this call created, for off()
    for _, mode in ipairs(text.aslist(modes)) do
      local o = {
        noremap = opts.noremap ~= false,
        silent = opts.silent or false,
        nowait = opts.nowait or false,
        expr = opts.expr or false,
      }
      local keys = ""
      if type(rhs) == "function" then
        if opts.expr then
          o.replace_keycodes = true
        end
        o.callback = function()
          -- `mode` is the declared mode for this mapping: deterministic and
          -- identical to the Vim backend (where mode() under <Cmd> is unreliable).
          return rhs({ count = vim.v.count, register = vim.v.register, mode = mode })
        end
      else
        keys = rhs
      end
      if opts.buffer then
        set_buf_keymap(0, mode, lhs, keys, core.dict(o))
      else
        set_keymap(mode, lhs, keys, core.dict(o))
      end
      created[#created + 1] = mode
    end

    local removed = false
    return {
      -- Idempotent: a second off() (or off() after an external delete) is a
      -- no-op. Removes the mapping for every mode this call created.
      off = function()
        if removed then
          return
        end
        removed = true
        for _, mode in ipairs(created) do
          if opts.buffer then
            pcall(del_buf_keymap, 0, mode, lhs)
          else
            pcall(del_keymap, mode, lhs)
          end
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
      if opts.buffer then
        del_buf_keymap(0, mode, lhs)
      else
        del_keymap(mode, lhs)
      end
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
    -- maparg(lhs, mode, abbr=false, dict=true) returns the rich dict on both
    -- editors; an absent mapping yields an empty dict (next() == nil).
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
