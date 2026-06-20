-- liv.lua.hash.sha1 — pure-Lua SHA-1 (RFC 3174 / FIPS 180). Editor-independent,
-- L1-testable. All 32-bit arithmetic goes through the liv.lua.compat bit shim
-- (no native bitwise operators, per the Lua-5.1 dialect rule). SHA-1 is
-- BIG-ENDIAN: message words, the appended bit-length, and the digest are all
-- most-significant byte first. `digest(s)` returns the raw 20 bytes (reused by
-- HMAC); `hexdigest(s)` is the lowercase hex wrapper.
local compat = require("liv.lua.compat")
local band, bor, bxor, bnot = compat.band, compat.bor, compat.bxor, compat.bnot
local lshift, rshift = compat.lshift, compat.rshift
local byte, char = string.byte, string.char
local floor = math.floor

local MASK = 0xFFFFFFFF

local function add32(a, b)
  return band(a + b, MASK)
end

local function rotl(x, n)
  return band(bor(lshift(x, n), rshift(x, 32 - n)), MASK)
end

-- Append the standard padding (0x80, then zeros, then the 64-bit BIG-ENDIAN bit
-- length) so the message length becomes a multiple of 64 bytes.
local function pad_message(s)
  local len = #s
  local bitlen = len * 8
  local pad = (56 - (len + 1) % 64) % 64
  local lenbytes = {}
  local n = bitlen
  for i = 8, 1, -1 do
    lenbytes[i] = char(n % 256)
    n = floor(n / 256)
  end
  return s .. char(0x80) .. string.rep("\0", pad) .. table.concat(lenbytes)
end

-- Compute the raw 20-byte SHA-1 digest of `s`.
---@param s string the message bytes
---@return string digest the 20 raw digest bytes
local function digest(s)
  local msg = pad_message(s)
  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0

  for chunk = 1, #msg, 64 do
    -- Read 16 big-endian 32-bit words, then extend to 80.
    local w = {}
    for i = 0, 15 do
      local p = chunk + i * 4
      local b1, b2, b3, b4 = byte(msg, p, p + 3)
      w[i] = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
    end
    for i = 16, 79 do
      w[i] = rotl(bxor(bxor(bxor(w[i - 3], w[i - 8]), w[i - 14]), w[i - 16]), 1)
    end

    local a, b, c, d, e = h0, h1, h2, h3, h4
    for i = 0, 79 do
      local f, k
      if i < 20 then
        f = bor(band(b, c), band(bnot(b), d))
        k = 0x5A827999
      elseif i < 40 then
        f = bxor(bxor(b, c), d)
        k = 0x6ED9EBA1
      elseif i < 60 then
        f = bor(bor(band(b, c), band(b, d)), band(c, d))
        k = 0x8F1BBCDC
      else
        f = bxor(bxor(b, c), d)
        k = 0xCA62C1D6
      end
      local temp = add32(add32(add32(add32(rotl(a, 5), f), e), k), w[i])
      e = d
      d = c
      c = rotl(b, 30)
      b = a
      a = temp
    end

    h0 = add32(h0, a)
    h1 = add32(h1, b)
    h2 = add32(h2, c)
    h3 = add32(h3, d)
    h4 = add32(h4, e)
  end

  -- Output the five words big-endian.
  local out = {}
  local words = { h0, h1, h2, h3, h4 }
  for wi = 1, 5 do
    local v = words[wi]
    out[#out + 1] = char(band(rshift(v, 24), 0xFF))
    out[#out + 1] = char(band(rshift(v, 16), 0xFF))
    out[#out + 1] = char(band(rshift(v, 8), 0xFF))
    out[#out + 1] = char(band(v, 0xFF))
  end
  return table.concat(out)
end

-- Hexadecimal (lowercase) SHA-1 digest of `s`.
---@param s string the message bytes
---@return string hex the 40-character lowercase hex digest
local function hexdigest(s)
  return (digest(s):gsub(".", function(c)
    return string.format("%02x", byte(c))
  end))
end

return { digest = digest, hexdigest = hexdigest, block_size = 64 }
