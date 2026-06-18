-- liv.lua.png encoder: raw pixels + geometry -> PNG bytes. Pure and
-- 5.1-compatible. It writes the signature, an IHDR (8-bit truecolour, color
-- type 2 or 6), a single IDAT (each scanline prefixed with a None filter byte
-- then deflated via liv.lua.zlib), and IEND. Every chunk carries its CRC-32.
local zlib = require("liv.lua.zlib")
local crc32 = require("liv.lua.png._crc")

local char = string.char
local sub = string.sub
local concat = table.concat
local floor = math.floor

local SIGNATURE = "\137PNG\r\n\26\n"

-- Encode a big-endian 32-bit unsigned integer as 4 bytes.
local function u32(v)
  return char(
    floor(v / 16777216) % 256,
    floor(v / 65536) % 256,
    floor(v / 256) % 256,
    v % 256
  )
end

-- Assemble one PNG chunk: length, type, data, then CRC-32 of (type .. data).
local function chunk(ctype, data)
  return u32(#data) .. ctype .. data .. u32(crc32(ctype .. data))
end

-- Encode an image table into PNG bytes.
---@param img { data: string, width: integer, height: integer, format: string }
---@return string bytes the PNG file contents
local function encode(img)
  local format = img.format
  local color_type
  local bpp
  if format == "rgb" then
    color_type, bpp = 2, 3
  elseif format == "rgba" then
    color_type, bpp = 6, 4
  else
    error("liv.lua.png: unsupported format " .. tostring(format))
  end

  local width, height = img.width, img.height
  local ihdr = u32(width)
    .. u32(height)
    .. char(8) -- bit depth
    .. char(color_type)
    .. char(0) -- compression
    .. char(0) -- filter method
    .. char(0) -- interlace

  -- Prepend a filter-type-0 (None) byte to each scanline of the raw pixels.
  local stride = width * bpp
  local rows = {}
  for y = 0, height - 1 do
    local start = y * stride + 1
    rows[#rows + 1] = char(0) .. sub(img.data, start, start + stride - 1)
  end
  local idat = zlib.deflate(concat(rows))

  return SIGNATURE
    .. chunk("IHDR", ihdr)
    .. chunk("IDAT", idat)
    .. chunk("IEND", "")
end

return encode
