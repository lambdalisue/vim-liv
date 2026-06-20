-- liv.lua.png — pure-Lua PNG codec (spec 0006, note §19). Editor-independent
-- and L1-testable. `decode(bytes) -> { data, width, height, format }` reads an
-- 8-bit truecolour PNG (color type 2 RGB / 6 RGBA, non-interlaced) into raw
-- pixels; `encode(img) -> bytes` writes one back. The compression seam is
-- liv.lua.zlib; chunk integrity uses a pure CRC-32.
---@class liv.lua.png
---@field decode fun(bytes: string): { data: string, width: integer, height: integer, format: string }
---@field encode fun(img: { data: string, width: integer, height: integer, format: string }): string
local decode = require("liv.lua.png.decode")
local encode = require("liv.lua.png.encode")

local M = {}
M.decode = decode
M.encode = encode
return M
