-- liv.std.window — window access (spec 0006). Editor-dependent; selects a
-- backend once at import. Conventions: a window handle is an integer id, with
-- 0/nil meaning the current window; positions are {line, col}, both 1-based.
local core = require("liv.core")

---@class liv.std.window.open.opts
---@field split? "above"|"below"|"left"|"right" split direction relative to current (default "below")
---@field size? integer height (above/below) or width (left/right) in cells
---@field focus? boolean focus the new window (default true; false keeps the current window focused)
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
---@field open fun(bufnr: integer, opts?: liv.std.window.open.opts): integer # display a caller-owned buffer in a new split window
---@field set_buffer fun(win: integer?, bufnr: integer) # swap the buffer shown in a window

---@type liv.std.window
return (core.is_nvim and require("liv.std.window._nvim") or require("liv.std.window._vim"))(core)
