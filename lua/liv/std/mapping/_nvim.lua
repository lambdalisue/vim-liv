-- liv.std.mapping Neovim backend: native nvim_set_keymap / nvim_buf_set_keymap. A
-- Lua-function rhs is passed as opts.callback (with an empty string rhs) and
-- wrapped to receive the liv context table; a string rhs is used as-is. For an
-- expr mapping the callback's return string is used as the keys (replace_keycodes
-- so `<...>` notation works).
local text = require("liv.lua.text")

return function(core)
  local set_keymap = core.marshaled(vim.api.nvim_set_keymap)
  local del_keymap = core.marshaled(vim.api.nvim_del_keymap)
  local set_buf_keymap = core.marshaled(vim.api.nvim_buf_set_keymap)
  local del_buf_keymap = core.marshaled(vim.api.nvim_buf_del_keymap)

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

  return M
end
