-- liv.lua.msgpack — pure-Lua msgpack codec (spec 0006). Editor-independent and
-- L1-testable; it shares the list/dict/NIL shape markers with liv.lua.value, so a
-- table tagged via core.list/core.dict (or value.empty_dict) serializes the same
-- way editor marshaling treats it. `encode(v) -> bytes`; `decode(s[, pos]) ->
-- value, next`. Streaming encoder/decoder can layer on these primitives later.
---@class liv.lua.msgpack
---@field encode fun(v: any): string
---@field decode fun(s: string, pos?: integer): any, integer
local pack = require("liv.lua.msgpack._pack")
local unpack = require("liv.lua.msgpack._unpack")

local M = {}
M.encode = pack.encode
M.decode = unpack.decode
return M
