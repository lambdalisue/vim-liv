-- liv.lua.png CRC-32: the PNG/ISO-3309 CRC used to validate and emit chunks.
-- Pure and 5.1-compatible. Table-driven; the running value stays in "bit-land"
-- (only band/bxor/rshift touch it) so LuaJIT's signed bit results never leak
-- into arithmetic.
local compat = require("liv.lua.compat")
local band, bxor, rshift = compat.band, compat.bxor, compat.rshift

-- Precompute the standard CRC-32 lookup table (polynomial 0xEDB88320).
local TABLE = {}
for n = 0, 255 do
  local c = n
  for _ = 1, 8 do
    if band(c, 1) == 1 then
      c = bxor(0xEDB88320, rshift(c, 1))
    else
      c = rshift(c, 1)
    end
  end
  TABLE[n] = c
end

-- CRC-32 of `s` (full message; no streaming state).
---@param s string the bytes to checksum
---@return integer crc the 32-bit CRC value (non-negative)
local function crc32(s)
  local crc = 0xFFFFFFFF
  for i = 1, #s do
    crc = bxor(rshift(crc, 8), TABLE[band(bxor(crc, s:byte(i)), 0xFF)])
  end
  crc = bxor(crc, 0xFFFFFFFF)
  -- Normalise LuaJIT's signed result back to a non-negative 32-bit integer.
  if crc < 0 then
    crc = crc + 4294967296
  end
  return crc
end

return crc32
