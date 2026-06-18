-- liv.core marshaling backend for Vim (+lua).
--
-- Vim's if_lua does NOT auto-convert Lua tables to List/Dict on input — they must
-- be wrapped with vim.list()/vim.dict() — and returns List/Dict as *userdata* on
-- output. Scalars convert directly; v:null becomes Lua nil. A nested v:null in a
-- list is counted by `#` but reads back as Lua nil, so decode iterates 1..#v and
-- treats an in-bounds nil as the NIL sentinel.
local value = require("liv.lua.value")

local M = {}

M.raw_eval = vim.eval

function M.raw_cmd(command)
  vim.command(command)
end

-- Cached editor sentinels (v:null / v:true / v:false).
local NULL = vim.eval("v:null")
local TRUE = vim.eval("v:true")
local FALSE = vim.eval("v:false")

function M.to_editor(v)
  if v == value.NIL then
    return NULL
  end
  local t = type(v)
  if t == "boolean" then
    return v and TRUE or FALSE
  end
  if t ~= "table" then
    return v -- number / string pass through
  end
  if value.classify(v) == "list" then
    local arr = {}
    for i = 1, #v do
      arr[i] = M.to_editor(v[i])
    end
    return vim.list(arr)
  end
  local d = {}
  for k, val in pairs(v) do
    d[tostring(k)] = M.to_editor(val)
  end
  return vim.dict(d)
end

function M.from_editor(v)
  local t = type(v)
  if t == "nil" then
    return value.NIL -- v:null (top-level, or an in-bounds list element)
  end
  if t ~= "userdata" then
    return v -- number / string / boolean
  end
  local kind = vim.type(v)
  if kind == "list" then
    local out = {}
    for i = 1, #v do
      out[i] = M.from_editor(v[i])
    end
    return out
  elseif kind == "dict" then
    local out = value.dict({})
    local keys = vim.fn.keys(v)
    for i = 1, #keys do
      local k = keys[i]
      out[k] = M.from_editor(v[k])
    end
    return out
  end
  return v -- funcref or other opaque userdata: pass through
end

return M
