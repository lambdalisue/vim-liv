-- liv.std.variable — scoped variables (spec 0006). Editor-dependent; selects a
-- backend once at import. The scope is a sub-table (no stringly-typed scope to
-- mistype): `var.g` global, `var.b` buffer, `var.w` window, `var.t` tab (the
-- current buffer/window/tab), `var.v` editor (v:), `var.r` register (@a..@z,
-- @", @0..@9, @*, @+, @/, …), `var.env` environment ($VAR) -- matching Vim's
-- g:/b:/w:/t:/v:/@/$ sigils. Each exposes get(name) / set(name, value). Values
-- cross through core marshaling, so lists/dicts/NIL round-trip.
--
-- Missing-value contract: it varies by scope, because "missing" means different
-- things across these namespaces:
--   * g/b/w/t/v -- an undefined variable returns nil on both editors (a missing
--     VALUE is nil, not an error and not Vim's empty-string default).
--   * r (registers) -- a register is never "undefined": it is a slot that always
--     exists, just possibly empty, so an unused register reads as "" (NOT nil).
--   * env (environment) -- an UNSET variable reads as nil, but a variable set to
--     "" reads as "" (unset and empty are distinct).
-- Setting a read-only v: var raises (an operation failure).
local core = require("liv.core")

local backend = (core.is_nvim and require("liv.std.variable._nvim") or require(
  "liv.std.variable._vim"
))(core)

-- A scoped-variable sub-table. get/set name a variable in the scope; values
-- cross through core marshaling, so lists/dicts/NIL round-trip.
---@class liv.std.variable.Scope
---@field get fun(name: string): any
---@field set fun(name: string, value: any)

---@class liv.std.variable
---@field g liv.std.variable.Scope Global variables (g:).
---@field b liv.std.variable.Scope Current-buffer variables (b:).
---@field w liv.std.variable.Scope Current-window variables (w:).
---@field t liv.std.variable.Scope Current-tab variables (t:).
---@field v liv.std.variable.Scope Editor variables (v:).
---@field r liv.std.variable.Scope Registers (@a..@z, @", @0..@9, @*, @+, @/, …); empty reads as "".
---@field env liv.std.variable.Scope Environment variables ($VAR); unset reads as nil.
local M = {}
for short, scope in pairs({
  g = "global",
  b = "buffer",
  w = "window",
  t = "tab",
  v = "vim",
  r = "register",
  env = "env",
}) do
  M[short] = {
    get = backend.get[scope],
    set = backend.set[scope],
  }
end

return M
