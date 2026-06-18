-- liv.std.variable — scoped variables (spec 0006). Editor-dependent; selects a
-- backend once at import. The scope is a sub-table (no stringly-typed scope to
-- mistype): `var.g` global, `var.b` buffer, `var.w` window, `var.t` tab (the
-- current buffer/window/tab), `var.v` editor (v:) -- matching Vim's
-- g:/b:/w:/t:/v: sigils. Each exposes get(name) / set(name, value). Values cross
-- through core marshaling, so lists/dicts/NIL round-trip.
--
-- Missing-value contract: an undefined variable returns nil on every scope on
-- both editors (a missing VALUE is nil, not an error and not Vim's empty-string
-- default). Setting a read-only v: var raises (an operation failure).
local core = require("liv.core")

local backend = (core.is_nvim and require("liv.std.variable._nvim") or require("liv.std.variable._vim"))(core)

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
local M = {}
for short, scope in pairs({ g = "global", b = "buffer", w = "window", t = "tab", v = "vim" }) do
  M[short] = {
    get = backend.get[scope],
    set = backend.set[scope],
  }
end

return M
