-- liv.lua.color — pure-Lua color math. Editor-independent, deterministic,
-- L1-testable. liv.std.highlight DEFINES colors (it takes fg/bg/sp as a
-- 0xRRGGBB integer or "#rrggbb" string) but owns no color MATH; this module is
-- the math an author composes around it:
--   * lighten/darken a group's color (via HSL) for a derived highlight;
--   * downgrade a truecolor value to the nearest xterm-256 index for a
--     256-color terminal Vim.
--
-- This is the barrel: it requires the three concern leaves and re-exposes their
-- flat API unchanged, so require("liv.lua.color") behaves exactly as before. A
-- consumer that needs only one concern requires that leaf directly instead —
-- e.g. require("liv.lua.color.xterm256") pulls the rgb leaf but neither the HSL
-- conversions nor the barrel.
--   * liv.lua.color.rgb      — parse / to_hex / rgb / to_rgb (representation)
--   * liv.lua.color.hsl      — hsl / to_hsl / lighten / darken (requires rgb)
--   * liv.lua.color.xterm256 — to_xterm256 / distance (requires rgb)
local rgb = require("liv.lua.color.rgb")
local hsl = require("liv.lua.color.hsl")
local xterm256 = require("liv.lua.color.xterm256")

---@class liv.lua.color
local M = {}

M.rgb = rgb.rgb
M.parse = rgb.parse
M.to_hex = rgb.to_hex
M.to_rgb = rgb.to_rgb

M.hsl = hsl.hsl
M.to_hsl = hsl.to_hsl
M.lighten = hsl.lighten
M.darken = hsl.darken

M.to_xterm256 = xterm256.to_xterm256
M.distance = xterm256.distance

return M
