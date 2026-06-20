-- liv.std.buffer — buffer access (spec 0006). Editor-dependent; selects a
-- backend once at import. Conventions: ranges are 1-based inclusive; a buffer
-- handle is an integer id, with 0/nil meaning the current buffer.
--
-- create reuse contract: create{name=X} returns the existing buffer of that name
-- if one exists (reuse), else creates a new one — identical on both editors.
local core = require("liv.core")

---@class liv.std.buffer
---@field lines fun(buf: integer?, first: integer, last: integer): string[]
---@field set_lines fun(buf: integer?, first: integer, last: integer, xs: string[])
---@field count fun(buf: integer?): integer
---@field name fun(buf: integer?): string
---@field valid fun(buf: integer?): boolean
---@field create fun(opts?: { listed?: boolean, scratch?: boolean, name?: string }): integer
---@field wipe fun(buf: integer?)
---@field with fun(buf: integer?, fn: fun(): any): any
---@field modifiable fun(buf: integer?, fn: fun(): any): any

---@type liv.std.buffer
return (core.is_nvim and require("liv.std.buffer._nvim") or require("liv.std.buffer._vim"))(core)
