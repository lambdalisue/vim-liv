-- liv.lua.value — value shape markers + classification (spec 0005, 0010).
--
-- Pure Lua, editor-independent. Lua has one table type for both lists and dicts,
-- but the editor and serialization formats (msgpack, JSON) distinguish them, so
-- this module owns the *decisions*: the list/dict tags, the NIL sentinel, and the
-- classify rule. It lives in liv.lua (not liv.core) so that both liv.core's
-- editor marshaling and the pure liv.lua codecs (e.g. liv.lua.msgpack) share the
-- same markers — a table tagged `dict` is honored identically everywhere. The
-- editor round-trip (userdata <-> table, v:null, v:true/false) is wired in
-- liv.core's primitives and exercised at L3.

local M = {}

-- Distinct metatables used only as identity tags. They carry no behaviour; a
-- table is "a list" or "a dict" purely by which one is its metatable.
local LIST_MT = {}
local DICT_MT = {}

-- Null sentinel: stands in for v:null / vim.NIL inside Lua tables (and a msgpack
-- nil), where a bare `nil` cannot live. Unique and stable for the process.
---@type table the null sentinel
M.NIL = setmetatable({}, {
  __tostring = function()
    return "liv.NIL"
  end,
})

-- Mark `t` (default a fresh table) as a list.
---@param t? table table to tag (default a fresh empty table)
---@return table list the same table, tagged as a list
function M.list(t)
  return setmetatable(t or {}, LIST_MT)
end

-- Mark `t` (default a fresh table) as a dict.
---@param t? table table to tag (default a fresh empty table)
---@return table dict the same table, tagged as a dict
function M.dict(t)
  return setmetatable(t or {}, DICT_MT)
end

-- A tagged empty dict; the only way to express an empty table as a Dict, since an
-- untagged empty table defaults to a list (see classify).
---@return table dict a fresh empty table tagged as a dict
function M.empty_dict()
  return M.dict({})
end

---@param t any value to test
---@return boolean is_list true when `t` is tagged as a list
function M.is_list(t)
  return getmetatable(t) == LIST_MT
end

---@param t any value to test
---@return boolean is_dict true when `t` is tagged as a dict
function M.is_dict(t)
  return getmetatable(t) == DICT_MT
end

-- Decide whether a table should be treated as a List or a Dict.
--
-- 1. explicit list tag      -> list   (highest priority)
-- 2. explicit dict tag      -> dict
-- 3. empty table            -> list   (default; use empty_dict() for a dict)
-- 4. proper 1..n sequence   -> list
-- 5. otherwise              -> dict
---@param t table table to classify
---@return "list"|"dict" kind the kind for `t`
function M.classify(t)
  local mt = getmetatable(t)
  if mt == LIST_MT then
    return "list"
  end
  if mt == DICT_MT then
    return "dict"
  end
  if next(t) == nil then
    return "list"
  end
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  if n == #t then
    return "list"
  end
  return "dict"
end

return M
