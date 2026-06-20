-- liv.lua.zlib deflater: bytes -> a valid zlib stream (RFC 1950). Pure and
-- 5.1-compatible. It emits only stored (uncompressed) DEFLATE blocks (BTYPE=00),
-- which are large but decompress correctly with any conforming inflater. The
-- stream is the zlib header (0x78 0x01), one or more stored blocks, then the
-- big-endian adler32 of the input.
local char = string.char
local sub = string.sub
local concat = table.concat

local MAX_BLOCK = 65535

-- Adler-32 over `s`: two rolling sums mod 65521. Plain modular arithmetic keeps
-- the values positive, so no bit ops are needed.
---@param s string the input bytes
---@return integer checksum the 32-bit adler32 value
local function adler32(s)
  local a, b = 1, 0
  for i = 1, #s do
    a = (a + s:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return b * 65536 + a
end

-- Emit one stored block header: a 1-byte BFINAL/BTYPE flag (BTYPE=00), then the
-- block length as little-endian LEN followed by its one's-complement NLEN.
local function stored_header(final, len)
  local nlen = 65535 - len
  return char(final and 1 or 0)
    .. char(len % 256)
    .. char(math.floor(len / 256))
    .. char(nlen % 256)
    .. char(math.floor(nlen / 256))
end

-- Deflate `s` into a valid zlib stream of stored blocks.
---@param s string the input bytes
---@return string stream a complete zlib stream
local function deflate(s)
  local parts = { char(0x78), char(0x01) }
  local n = #s
  if n == 0 then
    -- A valid stream still needs one (final, empty) block.
    parts[#parts + 1] = stored_header(true, 0)
  else
    local pos = 1
    while pos <= n do
      local len = n - pos + 1
      if len > MAX_BLOCK then
        len = MAX_BLOCK
      end
      local final = (pos + len - 1) == n
      parts[#parts + 1] = stored_header(final, len)
      parts[#parts + 1] = sub(s, pos, pos + len - 1)
      pos = pos + len
    end
  end

  local sum = adler32(s)
  -- adler32 trailer: big-endian.
  parts[#parts + 1] = char(
    math.floor(sum / 16777216) % 256,
    math.floor(sum / 65536) % 256,
    math.floor(sum / 256) % 256,
    sum % 256
  )
  return concat(parts)
end

return { deflate = deflate, adler32 = adler32 }
