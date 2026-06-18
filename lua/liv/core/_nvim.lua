-- liv.core marshaling backend for Neovim.
--
-- Neovim auto-converts between Lua tables and List/Dict, represents null as the
-- vim.NIL userdata, and preserves an empty dict via vim.empty_dict() (a table
-- with a distinct metatable). Booleans are native. So the converters are mostly
-- about the NIL sentinel and keeping an empty container's list/dict identity.
local value = require("liv.lua.value")

local M = {}

function M.raw_eval(expr)
  return vim.fn.eval(expr)
end

function M.raw_cmd(command)
  vim.api.nvim_command(command)
end

local EMPTY_DICT_MT = getmetatable(vim.empty_dict())

function M.to_editor(v)
  if v == value.NIL then
    return vim.NIL
  end
  local t = type(v)
  if t ~= "table" then
    return v -- number / string / boolean are native
  end
  if value.classify(v) == "list" then
    local arr = {}
    for i = 1, #v do
      arr[i] = M.to_editor(v[i])
    end
    return arr
  end
  if next(v) == nil then
    return vim.empty_dict()
  end
  local d = {}
  for k, val in pairs(v) do
    d[tostring(k)] = M.to_editor(val)
  end
  return d
end

function M.from_editor(v)
  if v == vim.NIL then
    return value.NIL
  end
  local t = type(v)
  if t ~= "table" then
    return v
  end
  if EMPTY_DICT_MT ~= nil and getmetatable(v) == EMPTY_DICT_MT then
    return value.empty_dict()
  end
  if value.classify(v) == "list" then
    local out = {}
    for i = 1, #v do
      out[i] = M.from_editor(v[i])
    end
    return out
  end
  local out = value.dict({})
  for k, val in pairs(v) do
    out[k] = M.from_editor(val)
  end
  return out
end

return M
