-- liv.std.callback — bind a Lua function to a Vim-callable function NAME (spec
-- 0006). Editor-dependent; selects a backend once at import.
--
-- Some editor features name a function by *string* and call it from a context
-- that cannot carry a Lua closure — most importantly the 'omnifunc' /
-- 'completefunc' buffer options, which name a function called as
-- `Func(findstart, base)`. `function_name(handler)` registers `handler` and
-- returns a string you can assign to such an option (via liv.std.option):
--
--   local callback = require("liv.std.callback")
--   local name = callback.function_name(function(findstart, base) ... end)
--   require("liv.std.option").b.set("omnifunc", name)
--
-- The handler runs on both editors with plain Lua values (args marshaled in, the
-- return marshaled back). On Vim the returned name is a generated forwarder bound
-- through the dispatch registry; on Neovim it is a `v:lua.…` reference into a
-- liv-owned global table. Either string is a valid value for omnifunc/completefunc
-- on its editor.
--
-- `release(name)` is the symmetric removal: pass back a name from function_name to
-- unregister the handler (freeing the held Funcref on Vim / the registry slot on
-- Neovim). It is idempotent — releasing twice, or a name that is not ours, is a
-- no-op on both editors.
local core = require("liv.core")

local backend = (core.is_nvim and require("liv.std.callback._nvim") or require("liv.std.callback._vim"))(core)

---@class liv.std.callback
local M = {}

-- Register `handler` and return a Vim function NAME (a string) that forwards to
-- it when called as `Func(a, b)`. Intended for the 'omnifunc'/'completefunc'
-- options. The handler receives plain Lua values and its return is marshaled back
-- to the editor (so an omnifunc returning a Lua list of dicts reaches Vim as a
-- List of Dicts, and an empty `{}` reaches it as an empty List).
---@param handler fun(a: any, b: any): any
---@return string func_name the value to assign to omnifunc/completefunc
function M.function_name(handler)
  return backend.function_name(handler)
end

-- Unregister a handler previously bound by function_name, freeing the editor-side
-- forwarder/registry slot. Idempotent on both editors.
---@param name string a value previously returned by function_name
function M.release(name)
  return backend.release(name)
end

return M
