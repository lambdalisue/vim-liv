-- liv.lua.color.rgb — the color REPRESENTATION concern: parse / to_hex / rgb /
-- to_rgb, plus the shared round/clamp/channel helpers the HSL and xterm256 leaves
-- compose around. Pure, zero-dependency: a consumer that needs only to parse or
-- format colors requires this leaf directly instead of the barrel, which would
-- also pull the HSL and xterm256 machinery.
--
-- Color representation is liv's own: a plain keyed table { r=, g=, b= } with each
-- channel an integer 0-255 (the keyed-table house style; lets parse -> to_hex
-- round-trip directly). It is deliberately NOT a packed 0xRRGGBB int internally —
-- the int and "#rrggbb" forms are I/O shapes (parse / to_hex), chosen because
-- that is exactly what liv.std.highlight accepts.
--
-- Channels carry no bitwise packing, so no compat bit shim is needed: the int <->
-- channel split is plain arithmetic (floor + %), matching the sibling
-- liv.lua.base64 reader. Conversions round (floor(x + 0.5)) rather than truncate,
-- so a half-lightness gray lands on 128 (#808080), not 127.
--
-- Failures raise via error() (pcall-able), per liv's contract — an unparseable
-- color is a programming error, not a nil to thread through.
local floor = math.floor
local format = string.format

---@class liv.lua.color.rgb
---@field r integer red channel, 0-255
---@field g integer green channel, 0-255
---@field b integer blue channel, 0-255

local M = {}

-- Round to nearest integer (half away from zero is irrelevant here: channels
-- and the conversions feeding this are non-negative).
local function round(x)
  return floor(x + 0.5)
end

-- Clamp `x` to the inclusive [lo, hi] range. Exposed as an internal-shared
-- helper (`_clamp`) so the HSL leaf can clamp saturation/lightness without
-- reimplementing it; the underscore marks it as not part of the public color
-- API a consumer composes (cf. png._crc, path._build).
local function clamp(x, lo, hi)
  if x < lo then
    return lo
  end
  if x > hi then
    return hi
  end
  return x
end
M._clamp = clamp

-- Round-and-clamp a channel into an integer 0-255.
local function channel(x)
  return clamp(round(x), 0, 255)
end

-- Build a color from raw r, g, b channels. Each is rounded to the nearest
-- integer and clamped into 0-255, so arithmetic results (e.g. from HSL) and
-- slightly out-of-range author input both normalize to a valid color.
---@param r number red channel
---@param g number green channel
---@param b number blue channel
---@return liv.lua.color.rgb
function M.rgb(r, g, b)
  return { r = channel(r), g = channel(g), b = channel(b) }
end

-- Parse a "#rgb" / "#rrggbb" string, OR a 0xRRGGBB integer, into a color.
-- The short "#rgb" form doubles each nibble (#abc -> #aabbcc). Hex is
-- case-insensitive. An invalid string, a non-integer number, or an integer
-- outside 0..0xffffff raises an error.
---@param input string|integer "#rgb" / "#rrggbb" or a 0xRRGGBB integer
---@return liv.lua.color.rgb
function M.parse(input)
  local t = type(input)
  if t == "number" then
    if input % 1 ~= 0 then
      error("liv.lua.color.parse: expected an integer, got " .. tostring(input))
    end
    if input < 0 or input > 0xffffff then
      error("liv.lua.color.parse: integer out of 0..0xffffff range: " .. tostring(input))
    end
    return {
      r = floor(input / 65536) % 256,
      g = floor(input / 256) % 256,
      b = input % 256,
    }
  elseif t == "string" then
    local hex = input:match("^#(%x+)$")
    if hex and #hex == 3 then
      local r, g, b = hex:sub(1, 1), hex:sub(2, 2), hex:sub(3, 3)
      return {
        r = tonumber(r .. r, 16),
        g = tonumber(g .. g, 16),
        b = tonumber(b .. b, 16),
      }
    elseif hex and #hex == 6 then
      return {
        r = tonumber(hex:sub(1, 2), 16),
        g = tonumber(hex:sub(3, 4), 16),
        b = tonumber(hex:sub(5, 6), 16),
      }
    end
    error("liv.lua.color.parse: not a '#rgb' or '#rrggbb' color: " .. input)
  end
  error("liv.lua.color.parse: expected a string or integer, got " .. t)
end

-- Format a color as a lowercase "#rrggbb" string — the form liv.std.highlight
-- accepts for fg/bg/sp.
---@param c liv.lua.color.rgb
---@return string
function M.to_hex(c)
  return format("#%02x%02x%02x", channel(c.r), channel(c.g), channel(c.b))
end

-- Return a color's channels as a tuple.
---@param c liv.lua.color.rgb
---@return integer r, integer g, integer b
function M.to_rgb(c)
  return c.r, c.g, c.b
end

return M
