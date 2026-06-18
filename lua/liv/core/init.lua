-- liv.core — the single, minimal seam over the editor (spec 0004).
--
-- The only namespace that touches `vim.*`. Exposes a few generic primitives plus
-- the marshaling API (re-exported from the pure liv.lua.value). `call` is shared
-- (both editors have `vim.call`); only `eval`/`cmd` and the value converters
-- branch by editor, in an is_nvim-selected backend (spec 0004 sanctions this as a
-- marshaling implementation detail, not feature branching).
local value = require("liv.lua.value")
local unpack = table.unpack or unpack

local is_nvim = vim ~= nil and vim.api ~= nil
local backend = is_nvim and require("liv.core._nvim") or require("liv.core._vim")

---@class liv.core
---@field is_nvim boolean true on Neovim, false on Vim
---@field NIL table the null sentinel (stands in for v:null inside Lua tables)
---@field list fun(t?: table): table tag a table as a list for marshaling
---@field dict fun(t?: table): table tag a table as a dict for marshaling
---@field empty_dict fun(): table a fresh empty table tagged as a dict
---@field is_list fun(t: any): boolean true when the value is tagged as a list
---@field is_dict fun(t: any): boolean true when the value is tagged as a dict
---@field to_editor fun(value: any): any convert a Lua value to its editor form
---@field from_editor fun(value: any): any convert an editor value to plain Lua
local M = {}

M.is_nvim = is_nvim

-- Marshaling API (pure tags; see spec 0005).
M.NIL = value.NIL
M.list = value.list
M.dict = value.dict
M.empty_dict = value.empty_dict
M.is_list = value.is_list
M.is_dict = value.is_dict

-- Value converters (editor-specific; the part of the seam that must stay
-- centralized). liv.std `_nvim` backends call the native API directly and cross
-- values through these; `_vim` backends use core.call below, which already
-- marshals. See spec 0004/0005.
M.to_editor = backend.to_editor
M.from_editor = backend.from_editor

-- Call a vimscript function (by name). Args and return value are marshaled both
-- ways, so the same plain Lua values are seen on both editors.
---@param fn string vimscript function name
---@param ... any arguments (marshaled to editor values)
---@return any result the function result (marshaled back to plain Lua)
function M.call(fn, ...)
  local n = select("#", ...)
  local args = {}
  for i = 1, n do
    args[i] = backend.to_editor((select(i, ...)))
  end
  return backend.from_editor(vim.call(fn, unpack(args, 1, n)))
end

-- Return `fn` with liv's bidirectional marshaling applied: a callable that
-- speaks plain Lua values (a function *reference* in, e.g.
-- vim.api.nvim_buf_get_lines). liv.std `_nvim` backends declare native bindings
-- once with this and then call them with plain Lua values: passing the real
-- symbol keeps completion and existence-checking, and marshaling can never be
-- forgotten. Named for liv's own marshaling vocabulary (spec 0005), and distinct
-- from liv.lua.async.wrap (a different transform). Editor-agnostic.
--
-- Memoized per function reference (weak keys), so wrapping the same symbol
-- returns the same wrapper instead of building a fresh closure each call.
local marshaled_cache = setmetatable({}, { __mode = "k" })

---@param fn function the function reference to wrap
---@return fun(...): any wrapped a callable that marshals args and result
function M.marshaled(fn)
  local cached = marshaled_cache[fn]
  if cached ~= nil then
    return cached
  end
  local wrapped = function(...)
    local n = select("#", ...)
    local args = {}
    for i = 1, n do
      args[i] = backend.to_editor((select(i, ...)))
    end
    return backend.from_editor(fn(unpack(args, 1, n)))
  end
  marshaled_cache[fn] = wrapped
  return wrapped
end

-- Evaluate a Vim expression string.
---@param expr string a Vim expression
---@return any result the evaluated value (marshaled to plain Lua)
function M.eval(expr)
  return backend.from_editor(backend.raw_eval(expr))
end

-- Run an Ex command string.
---@param command string an Ex command
function M.cmd(command)
  backend.raw_cmd(command)
end

return M
