-- liv.lua.msgpack unpacker: a msgpack byte string -> a Lua value. Pure and
-- 5.1-compatible. A msgpack nil decodes to liv.lua.value.NIL (a bare nil cannot
-- live in a Lua table); maps decode to dict-tagged tables and arrays to plain
-- sequences, so empty containers keep their list/dict identity on a round-trip.
-- Integers are exact to 2^53 (the Lua double limit).
--
-- Return shape: decode returns BOTH the value AND the next offset, because
-- msgpack is a stream codec (a buffer may hold several values back to back). This
-- two-value shape is intentional and specific to position codecs; whole-buffer
-- codecs in liv.lua (png/zlib decode, http parse) return a single value.
local value = require("liv.lua.value")

local byte = string.byte
local ssub = string.sub

-- Assert `s` holds at least `n` bytes starting at `pos`; otherwise raise the
-- module-prefixed error so truncated input fails the same branded way an
-- unsupported byte does (not an unguarded "arithmetic on a nil value").
local function need(s, pos, n)
  if pos < 1 or pos + n - 1 > #s then
    error(string.format("liv.lua.msgpack: truncated input (need %d byte(s) at %d)", n, pos))
  end
end

-- read a big-endian unsigned integer of width `w` (exact to 2^53)
local function rd_uint(s, pos, w)
  need(s, pos, w)
  local v = 0
  for i = 0, w - 1 do
    v = v * 256 + byte(s, pos + i)
  end
  return v, pos + w
end

-- read a big-endian signed integer of width `w` (1/2/4 bytes)
local function rd_int(s, pos, w)
  local v, p = rd_uint(s, pos, w)
  local half = 2 ^ (w * 8 - 1)
  if v >= half then
    v = v - half * 2
  end
  return v, p
end

-- 8-byte unsigned / signed via high+low 32-bit halves (exact to 2^53)
local function rd_u64(s, pos)
  local hi, p = rd_uint(s, pos, 4)
  local lo = rd_uint(s, p, 4)
  return hi * 4294967296 + lo, pos + 8
end

local function rd_i64(s, pos)
  local hi, p = rd_uint(s, pos, 4)
  local lo = rd_uint(s, p, 4)
  if hi >= 0x80000000 then -- negative: two's complement over 64 bits
    local mlo = (4294967296 - lo) % 4294967296
    local mhi = (mlo == 0 and lo == 0) and (4294967296 - hi) % 4294967296
      or (4294967296 - 1 - hi) % 4294967296
    return -(mhi * 4294967296 + mlo), pos + 8
  end
  return hi * 4294967296 + lo, pos + 8
end

-- decode an IEEE754 binary64 from 8 big-endian bytes
local function rd_double(s, pos)
  need(s, pos, 8)
  local b1, b2 = byte(s, pos), byte(s, pos + 1)
  local sign = (b1 >= 128) and -1 or 1
  local biased = (b1 % 128) * 16 + math.floor(b2 / 16)
  local mant = (b2 % 16) * 2 ^ 48 + select(1, rd_uint(s, pos + 2, 6))
  local v
  if biased == 0 then
    v = mant == 0 and 0.0 or mant * 2 ^ -1074 -- zero / subnormal
  elseif biased == 2047 then
    v = mant == 0 and math.huge or (0 / 0) -- inf / nan
  else
    v = (1 + mant / 2 ^ 52) * 2 ^ (biased - 1023)
  end
  return sign * v, pos + 8
end

-- decode an IEEE754 binary32 from 4 big-endian bytes (decode-only interop)
local function rd_float(s, pos)
  need(s, pos, 4)
  local n = select(1, rd_uint(s, pos, 4))
  local sign = (n >= 0x80000000) and -1 or 1
  local biased = math.floor(n / 8388608) % 256
  local mant = n % 8388608
  local v
  if biased == 0 then
    v = mant == 0 and 0.0 or mant * 2 ^ -149
  elseif biased == 255 then
    v = mant == 0 and math.huge or (0 / 0)
  else
    v = (1 + mant / 8388608) * 2 ^ (biased - 127)
  end
  return sign * v, pos + 4
end

local decode -- forward

local function decode_array(s, pos, n)
  local out = {}
  for i = 1, n do
    out[i], pos = decode(s, pos)
  end
  return out, pos
end

local function decode_map(s, pos, n)
  local out = value.dict({})
  for _ = 1, n do
    local k, v
    k, pos = decode(s, pos)
    v, pos = decode(s, pos)
    out[k] = v
  end
  return out, pos
end

function decode(s, pos)
  need(s, pos, 1)
  local b = byte(s, pos)
  pos = pos + 1
  if b <= 0x7f then
    return b, pos -- positive fixint
  elseif b >= 0xe0 then
    return b - 256, pos -- negative fixint
  elseif b >= 0x80 and b <= 0x8f then
    return decode_map(s, pos, b - 0x80)
  elseif b >= 0x90 and b <= 0x9f then
    return decode_array(s, pos, b - 0x90)
  elseif b >= 0xa0 and b <= 0xbf then
    local len = b - 0xa0
    need(s, pos, len)
    return ssub(s, pos, pos + len - 1), pos + len
  elseif b == 0xc0 then
    return value.NIL, pos
  elseif b == 0xc2 then
    return false, pos
  elseif b == 0xc3 then
    return true, pos
  elseif b == 0xca then
    return rd_float(s, pos)
  elseif b == 0xcb then
    return rd_double(s, pos)
  elseif b == 0xcc then
    return rd_uint(s, pos, 1)
  elseif b == 0xcd then
    return rd_uint(s, pos, 2)
  elseif b == 0xce then
    return rd_uint(s, pos, 4)
  elseif b == 0xcf then
    return rd_u64(s, pos)
  elseif b == 0xd0 then
    return rd_int(s, pos, 1)
  elseif b == 0xd1 then
    return rd_int(s, pos, 2)
  elseif b == 0xd2 then
    return rd_int(s, pos, 4)
  elseif b == 0xd3 then
    return rd_i64(s, pos)
  elseif b == 0xd9 or b == 0xda or b == 0xdb then
    local w = (b == 0xd9) and 1 or (b == 0xda) and 2 or 4
    local len
    len, pos = rd_uint(s, pos, w)
    need(s, pos, len)
    return ssub(s, pos, pos + len - 1), pos + len
  elseif b == 0xdc or b == 0xdd then
    local len
    len, pos = rd_uint(s, pos, b == 0xdc and 2 or 4)
    return decode_array(s, pos, len)
  elseif b == 0xde or b == 0xdf then
    local len
    len, pos = rd_uint(s, pos, b == 0xde and 2 or 4)
    return decode_map(s, pos, len)
  end
  error(string.format("liv.lua.msgpack: unsupported byte 0x%02x at %d", b, pos - 1))
end

local M = {}

-- Decode the msgpack value at `s` (optionally from 1-based `pos`).
---@param s string the msgpack bytes
---@param pos? integer 1-based start offset (default 1)
---@return any value the decoded value
---@return integer next the offset just past the decoded value
function M.decode(s, pos)
  return decode(s, pos or 1)
end

return M
