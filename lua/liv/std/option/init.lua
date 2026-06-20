-- liv.std.option — editor options (spec 0006). Editor-dependent; selects a
-- backend once at import. Scope is a sub-table: `option.g` global, `option.b`
-- buffer-local, `option.w` window-local, `option.l` local. Each supports:
--   - property access:  option.g.expandtab            (get)
--                       option.g.expandtab = true     (set)
--   - raw API:          option.g.get("expandtab") / option.g.set("expandtab", v)
-- Boolean options are normalized to Lua booleans on BOTH editors (Vim natively
-- reports them as 0/1) using the generated boolean-name set; values otherwise
-- cross through core marshaling. Editor-specific options live under
-- `option.vim.*` / `option.nvim.*` (typed to the vim-only / nvim-only sets;
-- the runtime scope tables are shared).
local core = require("liv.core")

-- The generated runtime metadata is a slim SET of boolean option names (the only
-- thing the runtime needs: whether to coerce a 0/1 get into a Lua boolean). The
-- full type/scope table lives in the require-free LuaLS annotations.
local bool_common = require("liv.std.option._generated")
local bool_plat = core.is_nvim and require("liv.std.option.nvim._generated")
  or require("liv.std.option.vim._generated")
local backend = (core.is_nvim and require("liv.std.option._nvim") or require("liv.std.option._vim"))(
  core
)

local function is_boolean(name)
  return bool_common[name] or bool_plat[name] or false
end

-- The buffer (.b) and window (.w) scopes accept an OPTIONAL trailing target
-- handle: option.b.get(name, buf?) / option.b.set(name, value, buf?) and likewise
-- option.w with a window id (buf/win default to current when omitted). Property
-- access always targets the current buffer/window. The global (.g) and local (.l)
-- scopes ignore the target arg.
local function make_scope(scope)
  local raw = {}

  function raw.get(name, target)
    local value = backend.get(scope, name, target)
    if is_boolean(name) and type(value) == "number" then
      value = value ~= 0
    end
    return value
  end

  function raw.set(name, value, target)
    backend.set(scope, name, value, target)
  end

  -- Reset an option to its default value within this scope. The reset is
  -- current-context: `g` resets the GLOBAL default (the value `g.get` reads), and
  -- `b`/`w`/`l` reset the LOCAL default for the current buffer/window (the value
  -- those scopes read). The `target` arg only accepts the current handle (nil/0);
  -- a non-current target has no native reset on either editor, so it raises rather
  -- than silently resetting the wrong context.
  function raw.reset(name, target)
    if target ~= nil and target ~= 0 then
      error("option." .. scope .. ".reset does not support a non-current target")
    end
    backend.reset(scope, name)
  end

  return setmetatable(raw, {
    __index = function(_, name)
      return raw.get(name)
    end,
    __newindex = function(_, name, value)
      raw.set(name, value)
    end,
  })
end

-- Type wiring for the language server. The generated classes liv.std.option.{
-- Common,Vim,Nvim} (in the _generated_annotations.lua files) enumerate the
-- option fields with their Lua types; a scope adds the raw get/set methods.
---@class liv.std.option.Scope : liv.std.option.Common
---@field get fun(name: string, target?: integer): boolean|integer|string
---@field set fun(name: string, value: boolean|integer|string, target?: integer)
---@field reset fun(name: string, target?: integer) reset to default (current context only)
---@class liv.std.option.VimScope : liv.std.option.Vim
---@field get fun(name: string): boolean|integer|string
---@field set fun(name: string, value: boolean|integer|string)
---@class liv.std.option.NvimScope : liv.std.option.Nvim
---@field get fun(name: string): boolean|integer|string
---@field set fun(name: string, value: boolean|integer|string)
---@class liv.std.option.VimNamespace
---@field g liv.std.option.VimScope
---@field b liv.std.option.VimScope
---@field w liv.std.option.VimScope
---@field l liv.std.option.VimScope
---@class liv.std.option.NvimNamespace
---@field g liv.std.option.NvimScope
---@field b liv.std.option.NvimScope
---@field w liv.std.option.NvimScope
---@field l liv.std.option.NvimScope
---@class liv.std.option
---@field g liv.std.option.Scope
---@field b liv.std.option.Scope
---@field w liv.std.option.Scope
---@field l liv.std.option.Scope
---@field vim liv.std.option.VimNamespace
---@field nvim liv.std.option.NvimNamespace
local M = {}
M.g = make_scope("g")
M.b = make_scope("b")
M.w = make_scope("w")
M.l = make_scope("l")

-- Editor-specific namespaces: the runtime is shared with the common scopes;
-- the generated annotations type option.vim.* / option.nvim.* to the
-- editor-specific option sets.
M.vim = { g = M.g, b = M.b, w = M.w, l = M.l }
M.nvim = { g = M.g, b = M.b, w = M.w, l = M.l }

return M
