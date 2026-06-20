-- liv.lua.color.xterm256 — the truecolor -> xterm-256 downgrade: to_xterm256 /
-- distance. Coerces a parseable input through the rgb leaf's parse, so it
-- requires only the rgb leaf — never the barrel, which would re-pull the HSL
-- machinery a 256-color quantizer does not need.
local rgb = require("liv.lua.color.rgb")

local M = {}

-- Coerce `c` to a color table: a table is taken as-is, anything else is parsed
-- via the rgb leaf. Lets to_xterm256 accept a parseable input directly.
local function coerce(c)
  if type(c) == "table" then
    return c
  end
  return rgb.parse(c)
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

return M
