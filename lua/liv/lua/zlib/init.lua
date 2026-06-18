-- liv.lua.zlib — pure-Lua zlib (RFC 1950) codec (spec 0006, note §19.1).
-- Editor-independent and L1-testable. `inflate(s) -> string` decompresses a
-- real zlib stream, including dynamic-Huffman DEFLATE bodies (RFC 1951);
-- `deflate(s) -> string` produces a valid round-trippable stream using stored
-- (uncompressed) blocks. Used by liv.lua.png for the IDAT image data.
---@class liv.lua.zlib
---@field inflate fun(s: string): string
---@field deflate fun(s: string): string
local inflate = require("liv.lua.zlib._inflate")
local deflate = require("liv.lua.zlib._deflate")

local M = {}
M.inflate = inflate.inflate
M.deflate = deflate.deflate
return M
