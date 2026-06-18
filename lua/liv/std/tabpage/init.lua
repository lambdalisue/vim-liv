-- liv.std.tabpage — tabpage access (spec 0006). Editor-dependent; selects a
-- backend once at import. A tabpage handle is an integer; 0/nil means current.
---@class liv.std.tabpage
---@field current fun(): integer
---@field all fun(): integer[]
---@field windows fun(tab: integer?): integer[]
local core = require("liv.core")

---@type liv.std.tabpage
return (core.is_nvim and require("liv.std.tabpage._nvim") or require("liv.std.tabpage._vim"))(core)
