-- liv.lua.color — pure-Lua color math. Editor-independent, deterministic,
-- L1-testable. liv.std.highlight DEFINES colors (it takes fg/bg/sp as a
-- 0xRRGGBB integer or "#rrggbb" string) but owns no color MATH; this module is
-- the math an author composes around it:
--   * lighten/darken a group's color (via HSL) for a derived highlight;
--   * downgrade a truecolor value to the nearest xterm-256 index for a
--     256-color terminal Vim.
--
-- Color representation is liv's own: a plain keyed table { r=, g=, b= } with
-- each channel an integer 0-255 (the keyed-table house style; lets parse ->
-- to_hex round-trip directly). It is deliberately NOT a packed 0xRRGGBB int
-- internally — the int and "#rrggbb" forms are I/O shapes (parse / to_hex),
-- chosen because that is exactly what liv.std.highlight accepts.
--
-- Channels carry no bitwise packing, so no compat bit shim is needed: the
-- int <-> channel split is plain arithmetic (floor + %), matching the sibling
-- liv.lua.base64 reader. Conversions round (floor(x + 0.5)) rather than
-- truncate, so a half-lightness gray lands on 128 (#808080), not 127.
--
-- Failures raise via error() (pcall-able), per liv's contract — an
-- unparseable color is a programming error, not a nil to thread through.
local floor = math.floor
local format = string.format

---@class liv.lua.color.rgb
---@field r integer red channel, 0-255
---@field g integer green channel, 0-255
---@field b integer blue channel, 0-255

---@class liv.lua.color
local M = {}

-- Round to nearest integer (half away from zero is irrelevant here: channels
-- and the conversions feeding this are non-negative).
local function round(x)
  return floor(x + 0.5)
end

-- Clamp `x` to the inclusive [lo, hi] range.
local function clamp(x, lo, hi)
  if x < lo then
    return lo
  end
  if x > hi then
    return hi
  end
  return x
end

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

-- Coerce `c` to a color table: a table is taken as-is, anything else is parsed.
-- Lets the convenience verbs (to_xterm256) accept a parseable input directly.
local function coerce(c)
  if type(c) == "table" then
    return c
  end
  return M.parse(c)
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

-- Convert HSL to a color. h is in degrees and wraps modulo 360; s and l are in
-- 0..1 (clamped). This is the standard chroma-based HSL->RGB: l=0 is black and
-- l=1 is white for any hue/saturation, s=0 is a gray at the given lightness.
---@param h number hue in degrees (wraps mod 360)
---@param s number saturation, 0..1
---@param l number lightness, 0..1
---@return liv.lua.color.rgb
function M.hsl(h, s, l)
  h = h % 360
  s = clamp(s, 0, 1)
  l = clamp(l, 0, 1)

  local c = (1 - math.abs(2 * l - 1)) * s
  local hp = h / 60
  local x = c * (1 - math.abs(hp % 2 - 1))
  local m = l - c / 2

  local r1, g1, b1
  if hp < 1 then
    r1, g1, b1 = c, x, 0
  elseif hp < 2 then
    r1, g1, b1 = x, c, 0
  elseif hp < 3 then
    r1, g1, b1 = 0, c, x
  elseif hp < 4 then
    r1, g1, b1 = 0, x, c
  elseif hp < 5 then
    r1, g1, b1 = x, 0, c
  else
    r1, g1, b1 = c, 0, x
  end

  return M.rgb((r1 + m) * 255, (g1 + m) * 255, (b1 + m) * 255)
end

-- Convert a color to HSL. h is in degrees 0..360, s and l in 0..1. The inverse
-- of hsl() within rounding (the RGB step quantizes channels to 0-255). A gray
-- (max == min) reports hue 0 and saturation 0.
---@param c liv.lua.color.rgb
---@return number h, number s, number l
function M.to_hsl(c)
  local r, g, b = c.r / 255, c.g / 255, c.b / 255
  local max = math.max(r, g, b)
  local min = math.min(r, g, b)
  local l = (max + min) / 2

  if max == min then
    return 0, 0, l -- achromatic
  end

  local d = max - min
  local s
  if l > 0.5 then
    s = d / (2 - max - min)
  else
    s = d / (max + min)
  end

  local h
  if max == r then
    h = (g - b) / d
    if g < b then
      h = h + 6
    end
  elseif max == g then
    h = (b - r) / d + 2
  else
    h = (r - g) / d + 4
  end
  h = h * 60

  return h, s, l
end

-- Euclidean distance between two colors in RGB space (equal channel weights).
-- Used for nearest-palette matching; sqrt keeps it a true metric, and since
-- sqrt is monotonic it is equally valid inside to_xterm256's nearest search.
---@param a liv.lua.color.rgb
---@param b liv.lua.color.rgb
---@return number
function M.distance(a, b)
  local dr = a.r - b.r
  local dg = a.g - b.g
  local db = a.b - b.b
  return math.sqrt(dr * dr + dg * dg + db * db)
end

-- The 6 levels the xterm-256 color cube samples each channel at.
local CUBE_LEVELS = { 0, 95, 135, 175, 215, 255 }

-- Snap a single channel value to the index (0-5) of the nearest cube level.
local function nearest_cube_index(v)
  local best, best_d = 0, math.huge
  for i = 1, 6 do
    local d = math.abs(v - CUBE_LEVELS[i])
    if d < best_d then
      best, best_d = i - 1, d
    end
  end
  return best
end

-- Quantize a truecolor RGB to the nearest xterm-256 palette index. This is the
-- truecolor -> 256 downgrade for terminal Vim without truecolor support.
--
-- The candidate palette is restricted to the 6x6x6 color cube (16-231) and the
-- 24-step grayscale ramp (232-255); the 16 system colors (0-15) are EXCLUDED
-- because they are terminal-themeable (not fixed RGB) and would otherwise win
-- exact matches like black/white/red, defeating the stable-cube mapping. The
-- winner is the candidate with the smallest RGB distance to the input.
---@param input liv.lua.color.rgb|string|integer a color or parseable color
---@return integer index xterm-256 palette index, 16-255
function M.to_xterm256(input)
  local c = coerce(input)

  -- Best cube candidate: snap each channel independently, then build its RGB.
  local ri = nearest_cube_index(c.r)
  local gi = nearest_cube_index(c.g)
  local bi = nearest_cube_index(c.b)
  local cube_rgb = {
    r = CUBE_LEVELS[ri + 1],
    g = CUBE_LEVELS[gi + 1],
    b = CUBE_LEVELS[bi + 1],
  }
  local cube_index = 16 + 36 * ri + 6 * gi + bi
  local cube_d = M.distance(c, cube_rgb)

  -- Best gray candidate: the ramp is value 8 + 10*i for i in 0..23.
  local best_gray_i, best_gray_d = 0, math.huge
  for i = 0, 23 do
    local v = 8 + 10 * i
    local d = M.distance(c, { r = v, g = v, b = v })
    if d < best_gray_d then
      best_gray_i, best_gray_d = i, d
    end
  end
  local gray_index = 232 + best_gray_i

  if best_gray_d < cube_d then
    return gray_index
  end
  return cube_index
end

-- Lighten a color by `amount` (0..1) of absolute HSL lightness, clamped at
-- white. Handy for deriving a hover/active variant of a highlight group.
---@param c liv.lua.color.rgb
---@param amount number lightness delta, 0..1
---@return liv.lua.color.rgb
function M.lighten(c, amount)
  local h, s, l = M.to_hsl(c)
  return M.hsl(h, s, clamp(l + amount, 0, 1))
end

-- Darken a color by `amount` (0..1) of absolute HSL lightness, clamped at
-- black. The inverse of lighten.
---@param c liv.lua.color.rgb
---@param amount number lightness delta, 0..1
---@return liv.lua.color.rgb
function M.darken(c, amount)
  local h, s, l = M.to_hsl(c)
  return M.hsl(h, s, clamp(l - amount, 0, 1))
end

return M
