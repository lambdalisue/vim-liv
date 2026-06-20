-- liv.std.mark — text decoration (spec 0006), a feasible cross-editor subset.
-- place() decorates a whole line (line highlight and/or virtual text shown after
-- the line); range() highlights an intra-line column span, optionally spanning
-- multiple lines. Both are power features: they raise if the requested decoration
-- is unavailable on the current editor, so authors gate with liv.std.has and degrade
-- intentionally rather than fail silently. Neovim uses extmarks; Vim uses text
-- properties. Both return an opaque id to pass back to remove(); clear() drops
-- every liv mark in a buffer. Handles follow liv's convention: buf 0/nil means the
-- current buffer.
--
-- Positions are {line, col}, 1-based, and ranges are INCLUSIVE on both ends (liv
-- convention). Columns are 1-based BYTE columns (not character indices): a caller
-- coloring multibyte text must pass byte offsets, matching how the underlying
-- editors address text-property/extmark columns.
---@class liv.std.mark.opts
---@field hl? string highlight group applied to the whole line
---@field virt_text? string virtual text shown after the line
---@field virt_text_hl? string highlight group for the virtual text (default: hl)
---@class liv.std.mark.range_opts
---@field hl string highlight group applied to the column span
---@class liv.std.mark
---@field place fun(buf: integer, line: integer, opts: liv.std.mark.opts): integer
---@field range fun(buf: integer, from: integer[], to: integer[], opts: liv.std.mark.range_opts): integer
---@field remove fun(buf: integer, id: integer)
---@field clear fun(buf: integer)
local core = require("liv.core")

---@type liv.std.mark
return (core.is_nvim and require("liv.std.mark._nvim") or require("liv.std.mark._vim"))(core)
