-- Compat shim (Axis A): smooths over Lua 5.1-5.4 / LuaJIT differences so the
-- rest of liv can be written in a single 5.1-compatible dialect.
--
-- Source elsewhere in liv MUST route version-sensitive operations through this
-- module instead of using 5.2+/5.3+ syntax (`goto`, `//`, `& | ~ << >>`) or
-- relying on functions that moved or were removed between versions.

---@class liv.lua.compat
---@field unpack fun(list: table, i?: integer, j?: integer): ... unpack a list
---@field pack fun(...): table pack varargs into a table with an `n` field
---@field searchers (fun(name: string): any)[] the module searcher list
---@field band fun(a: integer, b: integer): integer bitwise AND (unsigned 32-bit)
---@field bor fun(a: integer, b: integer): integer bitwise OR (unsigned 32-bit)
---@field bxor fun(a: integer, b: integer): integer bitwise XOR (unsigned 32-bit)
---@field lshift fun(a: integer, n: integer): integer left shift (unsigned 32-bit)
---@field rshift fun(a: integer, n: integer): integer right shift (unsigned 32-bit)
---@field bnot fun(a: integer): integer bitwise NOT (unsigned 32-bit)
local M = {}

-- unpack moved to table.unpack in 5.2; LuaJIT/5.1 expose it as a global.
M.unpack = table.unpack or unpack

-- table.pack arrived in 5.2; emulate it (with the `n` field) where absent.
M.pack = table.pack
  or function(...)
    return { n = select("#", ...), ... }
  end

-- package.loaders was renamed package.searchers in 5.2.
M.searchers = package.searchers or package.loaders

-- ---------------------------------------------------------------------------
-- Bitwise operations
--
-- The 5.3 operators (& | ~ << >>) are banned by the dialect rule, so callers
-- use these functions. Prefer a native bit library when present (LuaJIT `bit`,
-- 5.2 `bit32`); otherwise fall back to a pure-Lua 32-bit implementation that
-- works everywhere (notably plain 5.1 and 5.5, which have neither library).
-- ---------------------------------------------------------------------------

local TWO32 = 4294967296 -- 2^32

local function to32(n)
  n = n % TWO32
  if n < 0 then
    n = n + TWO32
  end
  return n
end

local function pure_binary(op)
  return function(a, b)
    a, b = to32(a), to32(b)
    local res, bit = 0, 1
    while a > 0 or b > 0 do
      local abit, bbit = a % 2, b % 2
      if op(abit, bbit) == 1 then
        res = res + bit
      end
      a = (a - abit) / 2
      b = (b - bbit) / 2
      bit = bit * 2
    end
    return res
  end
end

local ok_bit, bitlib = pcall(require, "bit") -- LuaJIT

if ok_bit then
  M.band, M.bor, M.bxor = bitlib.band, bitlib.bor, bitlib.bxor
  M.lshift, M.rshift = bitlib.lshift, bitlib.rshift
  -- LuaJIT bit ops are signed 32-bit; normalise bnot to unsigned for liv.
  function M.bnot(a)
    return to32(bitlib.bnot(a))
  end
elseif type(bit32) == "table" then
  M.band, M.bor, M.bxor = bit32.band, bit32.bor, bit32.bxor
  M.lshift, M.rshift, M.bnot = bit32.lshift, bit32.rshift, bit32.bnot
else
  M.band = pure_binary(function(x, y)
    return (x == 1 and y == 1) and 1 or 0
  end)
  M.bor = pure_binary(function(x, y)
    return (x == 1 or y == 1) and 1 or 0
  end)
  M.bxor = pure_binary(function(x, y)
    return (x ~= y) and 1 or 0
  end)
  function M.lshift(a, n)
    return to32(to32(a) * (2 ^ n))
  end
  function M.rshift(a, n)
    return math.floor(to32(a) / (2 ^ n))
  end
  function M.bnot(a)
    return TWO32 - 1 - to32(a)
  end
end

-- ---------------------------------------------------------------------------
-- Numeric helpers for removed/moved functions
-- ---------------------------------------------------------------------------

-- math.pow was removed in 5.3.
---@type fun(x: number, y: number): number x raised to the power y
M.pow = math.pow
  or function(x, y)
    return x ^ y
  end

-- Integer division (the `//` operator is banned by the dialect rule).
---@param a number dividend
---@param b number divisor
---@return integer quotient the floored quotient
function M.idiv(a, b)
  return math.floor(a / b)
end

-- Detect integrality without 5.3's math.type (which is absent on 5.1/LuaJIT).
---@param n any value to test
---@return boolean is_integer true when `n` is a finite integral number
function M.is_integer(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and n % 1 == 0
end

-- math.atan2 was folded into a 2-arg math.atan in 5.3.
---@type fun(y: number, x: number): number the arc tangent of y/x in radians
M.atan2 = math.atan2
  or function(y, x)
    return math.atan(y, x)
  end

-- math.frexp / math.ldexp were removed in 5.3; IEEE754 float (un)packing needs
-- them (e.g. liv.lua.msgpack). frexp splits x into a mantissa m in [0.5, 1) and
-- an exponent e with x = m * 2^e; ldexp is the inverse. The fallback guards
-- 0/inf/nan so the normalize loop can never spin.
---@type fun(x: number): number, integer mantissa and exponent
M.frexp = math.frexp
  or function(x)
    if x == 0 or x ~= x or x == math.huge or x == -math.huge then
      return x, 0
    end
    local m, e = math.abs(x), 0
    while m >= 1 do
      m = m / 2
      e = e + 1
    end
    while m < 0.5 do
      m = m * 2
      e = e - 1
    end
    return (x < 0) and -m or m, e
  end

---@type fun(m: number, e: integer): number m * 2^e
M.ldexp = math.ldexp
  or function(m, e)
    return m * 2 ^ e
  end

return M
