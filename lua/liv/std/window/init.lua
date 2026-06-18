-- liv.std.window — window access (spec 0006). Editor-dependent; selects a
-- backend once at import. Conventions: a window handle is an integer id, with
-- 0/nil meaning the current window; positions are {line, col}, both 1-based.
local core = require("liv.core")

---@class liv.std.window
---@field current fun(): integer
---@field all fun(): integer[]
---@field buffer fun(win: integer?): integer
---@field valid fun(win: integer?): boolean
---@field cursor fun(win: integer?): integer[] # {line, col}, both 1-based
---@field set_cursor fun(win: integer?, pos: integer[])
---@field focus fun(win: integer?)
---@field close fun(win: integer?)
---@field size fun(win: integer?): integer[] # {width, height}

---@type liv.std.window
return (core.is_nvim and require("liv.std.window._nvim") or require("liv.std.window._vim"))(core)
