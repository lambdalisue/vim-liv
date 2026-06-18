-- liv.std.popup — floating/popup windows (spec 0006). Editor-dependent; selects a
-- backend once at import. A float is a *display overlay*: the common ground
-- between Neovim floating windows and Vim popups — non-focusable and not
-- interactive (an editable/focusable float is a Neovim-only power feature, out of
-- this base contract). `open(content, opts)` shows `content` (a string, split on
-- newlines, or a list of lines) and returns a window handle; `close`/`move`/
-- `resize` act on that handle. Positions are liv's own 1-based `{line, col}`.
---@class liv.std.popup.opts
---@field line? integer 1-based editor row of the top-left corner (default 1)
---@field col? integer 1-based editor column of the top-left corner (default 1)
---@field width? integer width in cells (default: widest line)
---@field height? integer height in rows (default: number of lines)
---@field border? boolean|"single"|"double"|"rounded" draw a border (true = "single")
---@field title? string a title shown on the top border (requires a border)
---@class liv.std.popup
---@field open fun(content: string|string[], opts?: liv.std.popup.opts): integer
---@field close fun(win: integer)
---@field move fun(win: integer, pos: { line: integer, col: integer })
---@field resize fun(win: integer, size: { width: integer, height: integer })
local core = require("liv.core")

---@type liv.std.popup
return (core.is_nvim and require("liv.std.popup._nvim") or require("liv.std.popup._vim"))(core)
