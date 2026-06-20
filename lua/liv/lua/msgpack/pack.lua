-- liv.lua.msgpack packer: a Lua value -> a msgpack byte string. Pure and
-- 5.1-compatible (no string.pack; floats via the compat frexp). Shape decisions
-- (list vs map, the NIL sentinel) come from liv.lua.value, so a table tagged with
-- core.list/core.dict marshals consistently here too. Lua numbers are doubles, so
-- integers are exact to 2^53; larger magnitudes lose precision (the host limit).
local value = require("liv.lua.value")
local compat = require("liv.lua.compat")
local frexp = compat.frexp
local is_integer = compat.is_integer

local schar = string.char
local floor = math.floor

-- big-endian unsigned bytes of width `w` (exact for values up to 2^53)
local function be(n, w)
  local out = {}
  for i = w, 1, -1 do
    out[i] = schar(n % 256)
    n = floor(n / 256)
  end
  return table.concat(out)
end

-- 8 big-endian bytes of a double in IEEE754 binary64.
local function pack_double(x)
  local sign = 0
  if x < 0 or (x == 0 and 1 / x < 0) then -- handle negative zero
    sign = 1
    x = -x
  end
  if x ~= x then -- NaN
    return schar(0x7f, 0xf8) .. string.rep("\0", 6)
  elseif x == math.huge then
    return schar(sign * 128 + 0x7f, 0xf0) .. string.rep("\0", 6)
  elseif x == 0 then
    return schar(sign * 128) .. string.rep("\0", 7)
  end
  local m, e = frexp(x) -- x = m * 2^e, 0.5 <= m < 1
  local biased = e - 1 + 1023 -- IEEE: x = (m*2) * 2^(e-1), m*2 in [1,2)
  local mant = floor((m * 2 - 1) * 2 ^ 52 + 0.5) -- 52-bit mantissa (exact; +0.5 absorbs fp noise)
  local b1 = sign * 128 + floor(biased / 16)
  local b2 = (biased % 16) * 16 + floor(mant / 2 ^ 48)
  return schar(b1, b2) .. be(mant % 2 ^ 48, 6)
end

local encode -- forward

local function encode_int(w, n)
  if n >= 0 then
    if n < 128 then
      w(schar(n)) -- positive fixint
    elseif n < 256 then
      w(schar(0xcc) .. be(n, 1))
    elseif n < 65536 then
      w(schar(0xcd) .. be(n, 2))
    elseif n < 4294967296 then
      w(schar(0xce) .. be(n, 4))
    else -- uint64 (exact to 2^53)
      w(schar(0xcf) .. be(floor(n / 4294967296), 4) .. be(n % 4294967296, 4))
    end
  else
    if n >= -32 then
      w(schar(256 + n)) -- negative fixint (0xe0..0xff)
    elseif n >= -128 then
      w(schar(0xd0) .. be(n % 256, 1))
    elseif n >= -32768 then
      w(schar(0xd1) .. be(n % 65536, 2))
    elseif n >= -2147483648 then
      w(schar(0xd2) .. be(n % 4294967296, 4))
    else -- int64 two's complement, computed via high/low 32-bit halves
      local mag = -n
      local lo = mag % 4294967296
      local hi = floor(mag / 4294967296)
      lo = (4294967296 - lo) % 4294967296
      hi = (lo == 0) and (4294967296 - hi) % 4294967296 or (4294967296 - 1 - hi) % 4294967296
      w(schar(0xd3) .. be(hi, 4) .. be(lo, 4))
    end
  end
end

local function encode_str(w, s)
  local len = #s
  if len < 32 then
    w(schar(0xa0 + len) .. s)
  elseif len < 256 then
    w(schar(0xd9) .. be(len, 1) .. s)
  elseif len < 65536 then
    w(schar(0xda) .. be(len, 2) .. s)
  else
    w(schar(0xdb) .. be(len, 4) .. s)
  end
end

local function encode_array(w, t, n)
  if n < 16 then
    w(schar(0x90 + n))
  elseif n < 65536 then
    w(schar(0xdc) .. be(n, 2))
  else
    w(schar(0xdd) .. be(n, 4))
  end
  for i = 1, n do
    encode(w, t[i])
  end
end

local function encode_map(w, t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  if n < 16 then
    w(schar(0x80 + n))
  elseif n < 65536 then
    w(schar(0xde) .. be(n, 2))
  else
    w(schar(0xdf) .. be(n, 4))
  end
  for k, v in pairs(t) do
    encode(w, k)
    encode(w, v)
  end
end

function encode(w, v)
  if v == nil or v == value.NIL then
    w(schar(0xc0))
  elseif v == true then
    w(schar(0xc3))
  elseif v == false then
    w(schar(0xc2))
  else
    local t = type(v)
    if t == "number" then
      -- Only encode as an integer within the exactly-representable range; a
      -- larger integral double (e.g. 1e300) must go out as float64, or the
      -- 8-byte integer extraction would silently lose its low bits.
      if is_integer(v) and v <= 9007199254740992 and v >= -9007199254740992 then
        encode_int(w, v)
      else
        w(schar(0xcb) .. pack_double(v))
      end
    elseif t == "string" then
      encode_str(w, v)
    elseif t == "table" then
      if value.classify(v) == "list" then
        encode_array(w, v, #v)
      else
        encode_map(w, v)
      end
    else
      error("liv.lua.msgpack: cannot encode a " .. t)
    end
  end
end

local M = {}

-- Encode a Lua value to a msgpack byte string.
---@param v any the value to encode
---@return string bytes the msgpack encoding
function M.encode(v)
  local parts = {}
  local function w(s)
    parts[#parts + 1] = s
  end
  encode(w, v)
  return table.concat(parts)
end

return M
