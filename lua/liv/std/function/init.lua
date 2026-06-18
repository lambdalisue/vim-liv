-- liv.std.function — typed wrappers over vimscript builtin functions (spec 0006).
-- Editor-dependent. The runtime is a thin forwarding metatable: fn.getline(1)
-- binds vim.fn.getline as a marshaled reference (core.marshaled) and calls it, so
-- marshaling stays centralized in core — the same shape every _vim/_nvim backend
-- uses. vim.fn exists on both editors. There is no per-function runtime code --
-- the typing comes from the generated LuaLS classes liv.std.function.{Common,Vim,Nvim}
-- (in the _generated_annotations.lua files), which give completion and
-- parameter/return types. Editor-specific builtins live under fn.vim.* / fn.nvim.*.
local core = require("liv.core")

local function forwarder()
  local cache = {}
  return setmetatable({}, {
    __index = function(_, name)
      local f = cache[name]
      if not f then
        f = core.marshaled(vim.fn[name]) -- bind the builtin once, marshaled
        cache[name] = f
      end
      return f
    end,
  })
end

---@class liv.std.function : liv.std.function.Common
---@field vim liv.std.function.Vim
---@field nvim liv.std.function.Nvim

---@type liv.std.function
local M = forwarder()
M.vim = forwarder()
M.nvim = forwarder()

return M
