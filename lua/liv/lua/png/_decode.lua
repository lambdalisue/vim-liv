-- liv.lua.png decoder: PNG bytes -> raw pixel data plus geometry. Pure and
-- 5.1-compatible. It verifies the signature, walks the chunk stream, reads
-- IHDR, inflates the concatenated IDAT data via liv.lua.zlib, then unfilters
-- every scanline (None/Sub/Up/Average/Paeth). Only the 8-bit, non-interlaced
-- truecolour formats are supported: color type 2 (RGB) and 6 (RGBA).
local zlib = require("liv.lua.zlib")

local byte = string.byte
local char = string.char
local sub = string.sub
local concat = table.concat
local floor = math.floor

local unpack = require("liv.lua.compat").unpack

local SIGNATURE = "\137PNG\r\n\26\n"

-- Read a big-endian 32-bit unsigned integer at 1-based `pos`. Raises the
-- module-prefixed error on truncated input (rather than an unguarded "arithmetic
-- on a nil value" when a byte runs past the end).
local function rd_u32(s, pos)
  if pos < 1 or pos + 3 > #s then
    error("liv.lua.png: truncated input (need 4 bytes at " .. tostring(pos) .. ")")
  end
  local a, b, c, d = byte(s, pos, pos + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

-- The Paeth predictor (RFC 2083): pick a/b/c by closeness to a+b-c.
local function paeth(a, b, c)
  local p = a + b - c
  local pa = math.abs(p - a)
  local pb = math.abs(p - b)
  local pc = math.abs(p - c)
  if pa <= pb and pa <= pc then
    return a
  elseif pb <= pc then
    return b
  end
  return c
end

-- Reverse the per-scanline filters, producing the raw pixel bytes. `bpp` is the
-- byte stride of one pixel; `raw` is the filtered image (filter byte + row data
-- per scanline). Returns the concatenated unfiltered pixel rows.
local function unfilter(raw, width, height, bpp)
  local stride = width * bpp
  -- Each scanline is one filter byte plus `stride` data bytes; bail with a
  -- branded error if the inflated data is short rather than reading past its end.
  if #raw < height * (stride + 1) then
    error("liv.lua.png: truncated pixel data")
  end
  local out = {}
  local prev = {}
  for i = 1, stride do
    prev[i] = 0
  end
  local pos = 1
  for _ = 1, height do
    local ft = byte(raw, pos)
    pos = pos + 1
    local cur = {}
    for i = 1, stride do
      local x = byte(raw, pos)
      pos = pos + 1
      local a = (i > bpp) and cur[i - bpp] or 0
      local b = prev[i]
      local c = (i > bpp) and prev[i - bpp] or 0
      local v
      if ft == 0 then
        v = x
      elseif ft == 1 then
        v = (x + a) % 256
      elseif ft == 2 then
        v = (x + b) % 256
      elseif ft == 3 then
        v = (x + floor((a + b) / 2)) % 256
      elseif ft == 4 then
        v = (x + paeth(a, b, c)) % 256
      else
        error("liv.lua.png: unknown filter type " .. tostring(ft))
      end
      cur[i] = v
    end
    -- Build the row string in bounded chunks to keep string.char arglists sane.
    local chunks = {}
    local ci = 1
    for i = 1, stride, 64 do
      local hi = i + 63
      if hi > stride then
        hi = stride
      end
      chunks[ci] = char(unpack(cur, i, hi))
      ci = ci + 1
    end
    out[#out + 1] = concat(chunks)
    prev = cur
  end
  return concat(out)
end

-- Decode a PNG image into raw pixels and geometry.
---@param bytes string the PNG file contents
---@return { data: string, width: integer, height: integer, format: string }
local function decode(bytes)
  if sub(bytes, 1, 8) ~= SIGNATURE then
    error("liv.lua.png: invalid PNG signature")
  end

  local pos = 9
  local width, height, color_type
  local idat = {}
  local n = #bytes
  while pos <= n do
    local length = rd_u32(bytes, pos)
    local ctype = sub(bytes, pos + 4, pos + 7)
    local data_start = pos + 8
    if ctype == "IHDR" then
      width = rd_u32(bytes, data_start)
      height = rd_u32(bytes, data_start + 4)
      local bit_depth = byte(bytes, data_start + 8)
      color_type = byte(bytes, data_start + 9)
      local interlace = byte(bytes, data_start + 12)
      if bit_depth ~= 8 then
        error("liv.lua.png: only 8-bit depth is supported")
      end
      if color_type ~= 2 and color_type ~= 6 then
        error("liv.lua.png: only color type 2 (RGB) or 6 (RGBA) is supported")
      end
      if interlace ~= 0 then
        error("liv.lua.png: interlaced images are not supported")
      end
    elseif ctype == "IDAT" then
      idat[#idat + 1] = sub(bytes, data_start, data_start + length - 1)
    elseif ctype == "IEND" then
      break
    end
    pos = data_start + length + 4 -- data + 4-byte CRC
  end

  if not width then
    error("liv.lua.png: missing IHDR chunk")
  end

  local bpp = (color_type == 6) and 4 or 3
  local raw = zlib.inflate(concat(idat))
  local data = unfilter(raw, width, height, bpp)
  return {
    data = data,
    width = width,
    height = height,
    format = (color_type == 6) and "rgba" or "rgb",
  }
end

return decode
