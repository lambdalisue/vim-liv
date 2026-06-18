-- liv.std.json — JSON encode/decode (spec 0006). Editor-dependent; selects a
-- backend once at import. Both backends produce identical, compact output (no
-- insignificant whitespace) and integrate with liv's value marshaling, so NIL /
-- empty containers / lists / dicts round-trip. (Neovim uses the native compact
-- vim.json; Vim uses json_encode/json_decode -- vim.fn.json_encode on Neovim
-- would emit spaces, hence the split.)
---@class liv.std.json
---@field encode fun(value: any): string
---@field decode fun(json: string): any
local core = require("liv.core")

---@type liv.std.json
return (core.is_nvim and require("liv.std.json._nvim") or require("liv.std.json._vim"))(core)
