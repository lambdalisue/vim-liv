-- liv.lua.color.hsl — the HSL concern: hsl / to_hsl / lighten / darken. Builds
-- colors through the rgb leaf (its constructor rounds+clamps channels) and reuses
-- the rgb leaf's clamp helper for saturation/lightness, so it requires only the
-- rgb leaf — never the barrel, which would re-pull the xterm256 machinery.
--
-- lighten/darken shift absolute HSL lightness (clamped at white/black), handy for
-- deriving a hover/active variant of a highlight group.
local rgb = require("liv.lua.color.rgb")

local clamp = rgb._clamp

local M = {}

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

  return rgb.rgb((r1 + m) * 255, (g1 + m) * 255, (b1 + m) * 255)
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
