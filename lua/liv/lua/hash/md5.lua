-- liv.lua.hash.md5 — pure-Lua MD5 (RFC 1321). Editor-independent, L1-testable.
-- All 32-bit arithmetic goes through the liv.lua.compat bit shim (no native
-- bitwise operators, per the Lua-5.1 dialect rule). MD5 is LITTLE-ENDIAN: the
-- message words and the appended bit-length are read/written least-significant
-- byte first, and so is the final digest. `digest(s)` returns the raw 16 bytes
-- (reused by HMAC); `hexdigest(s)` is the lowercase hex wrapper.
local compat = require("liv.lua.compat")
local band, bor, bxor, bnot = compat.band, compat.bor, compat.bxor, compat.bnot
local lshift, rshift = compat.lshift, compat.rshift
local byte, char = string.byte, string.char
local floor = math.floor

local MASK = 0xFFFFFFFF

-- Per-round left-rotate amounts and the precomputed sine-derived constants K.
local S = {
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
}
local K = {
  0xd76aa478,
  0xe8c7b756,
  0x242070db,
  0xc1bdceee,
  0xf57c0faf,
  0x4787c62a,
  0xa8304613,
  0xfd469501,
  0x698098d8,
  0x8b44f7af,
  0xffff5bb1,
  0x895cd7be,
  0x6b901122,
  0xfd987193,
  0xa679438e,
  0x49b40821,
  0xf61e2562,
  0xc040b340,
  0x265e5a51,
  0xe9b6c7aa,
  0xd62f105d,
  0x02441453,
  0xd8a1e681,
  0xe7d3fbc8,
  0x21e1cde6,
  0xc33707d6,
  0xf4d50d87,
  0x455a14ed,
  0xa9e3e905,
  0xfcefa3f8,
  0x676f02d9,
  0x8d2a4c8a,
  0xfffa3942,
  0x8771f681,
  0x6d9d6122,
  0xfde5380c,
  0xa4beea44,
  0x4bdecfa9,
  0xf6bb4b60,
  0xbebfbc70,
  0x289b7ec6,
  0xeaa127fa,
  0xd4ef3085,
  0x04881d05,
  0xd9d4d039,
  0xe6db99e5,
  0x1fa27cf8,
  0xc4ac5665,
  0xf4292244,
  0x432aff97,
  0xab9423a7,
  0xfc93a039,
  0x655b59c3,
  0x8f0ccc92,
  0xffeff47d,
  0x85845dd1,
  0x6fa87e4f,
  0xfe2ce6e0,
  0xa3014314,
  0x4e0811a1,
  0xf7537e82,
  0xbd3af235,
  0x2ad7d2bb,
  0xeb86d391,
}

local function add32(a, b)
  return band(a + b, MASK)
end

local function rotl(x, n)
  return band(bor(lshift(x, n), rshift(x, 32 - n)), MASK)
end

-- Append the standard padding (0x80, then zeros, then the 64-bit LITTLE-ENDIAN
-- bit length) so the message length becomes a multiple of 64 bytes.
local function pad_message(s)
  local len = #s
  local bitlen = len * 8
  local pad = (56 - (len + 1) % 64) % 64
  local tail = { char(0x80), string.rep("\0", pad) }
  -- 64-bit length, little-endian (8 bytes).
  local lenbytes = {}
  local n = bitlen
  for i = 1, 8 do
    lenbytes[i] = char(n % 256)
    n = floor(n / 256)
  end
  tail[#tail + 1] = table.concat(lenbytes)
  return s .. table.concat(tail)
end

-- Compute the raw 16-byte MD5 digest of `s`.
---@param s string the message bytes
---@return string digest the 16 raw digest bytes
local function digest(s)
  local msg = pad_message(s)
  local a0, b0, c0, d0 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476

  for chunk = 1, #msg, 64 do
    -- Read 16 little-endian 32-bit words from this 64-byte block.
    local m = {}
    for i = 0, 15 do
      local p = chunk + i * 4
      local b1, b2, b3, b4 = byte(msg, p, p + 3)
      m[i] = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    end

    local a, b, c, d = a0, b0, c0, d0
    for i = 0, 63 do
      local f, g
      if i < 16 then
        f = bor(band(b, c), band(bnot(b), d))
        g = i
      elseif i < 32 then
        f = bor(band(d, b), band(bnot(d), c))
        g = (5 * i + 1) % 16
      elseif i < 48 then
        f = bxor(bxor(b, c), d)
        g = (3 * i + 5) % 16
      else
        f = bxor(c, bor(b, band(bnot(d), MASK)))
        g = (7 * i) % 16
      end
      f = add32(add32(add32(f, a), K[i + 1]), m[g])
      a = d
      d = c
      c = b
      b = add32(b, rotl(f, S[i + 1]))
    end

    a0 = add32(a0, a)
    b0 = add32(b0, b)
    c0 = add32(c0, c)
    d0 = add32(d0, d)
  end

  -- Output the four words little-endian.
  local out = {}
  local words = { a0, b0, c0, d0 }
  for w = 1, 4 do
    local v = words[w]
    for _ = 1, 4 do
      out[#out + 1] = char(v % 256)
      v = floor(v / 256)
    end
  end
  return table.concat(out)
end

-- Hexadecimal (lowercase) MD5 digest of `s`.
---@param s string the message bytes
---@return string hex the 32-character lowercase hex digest
local function hexdigest(s)
  return (digest(s):gsub(".", function(c)
    return string.format("%02x", byte(c))
  end))
end

return { digest = digest, hexdigest = hexdigest, block_size = 64 }
