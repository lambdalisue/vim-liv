-- liv.lua.text — pure text helpers (spec 0006). Editor-independent, deterministic,
-- L1-testable. Two concerns the editor-dependent backends (popup, mapping) share
-- instead of each hand-rolling a byte-identical copy: coercing display content /
-- arguments into lists, and display-width string operations.
--
-- This is the barrel: it requires the two concern leaves and re-exposes their
-- flat API unchanged, so require("liv.lua.text") behaves exactly as before. A
-- consumer that needs only one concern requires that leaf directly instead —
-- e.g. require("liv.lua.text.coerce") pulls neither chars nor the display-width
-- algorithms.
--   * liv.lua.text.coerce — lines / aslist (content/argument coercion, zero deps)
--   * liv.lua.text.width  — chars / truncate / pad / align / wrap (display width)
local coerce = require("liv.lua.text.coerce")
local width = require("liv.lua.text.width")

---@class liv.lua.text
local M = {}

M.lines = coerce.lines
M.aslist = coerce.aslist

M.chars = width.chars
M.truncate = width.truncate
M.pad = width.pad
M.align = width.align
M.wrap = width.wrap

return M
