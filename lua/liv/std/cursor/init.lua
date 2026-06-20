-- liv.std.cursor — make the editor's terminal/GUI cursor invisible or visible
-- again (spec 0006). The typical caller hides the cursor while painting a custom
-- UI (a popup, a progress bar) and shows it again when done.
--
-- The cursor is a terminal/GUI concern, so the mechanism differs per editor and
-- is a power feature gated by has("cursor.hide") (statically true on both
-- editors; the GUI-vs-terminal nuance is a documented degradation, not an
-- availability gate — see the backend notes):
--
--   * Neovim drives the cursor shape through the 'guicursor' option plus a
--     'Cursor' highlight; the backend saves 'guicursor', defines a self-contained
--     fully-blended hidden highlight, and points every mode at it, then restores
--     the saved 'guicursor' on show().
--   * Vim's terminal honours the 't_ve' (cursor visible) / 't_vi' (cursor
--     invisible) termcap strings; the backend saves 't_ve' and sets it to 't_vi'
--     to hide, restoring the saved 't_ve' on show(). GUI Vim ignores termcap and
--     uses 'guicursor' instead, so on GUI Vim hide()/show() do not affect the
--     visible cursor — a documented degradation.
--
-- Both verbs are idempotent: state lives INTERNAL to the backend (the saved prior
-- value plus a hidden flag), so double-hide / double-show / show-before-hide are
-- no-ops net of state, and show() after hide() restores the exact prior
-- appearance.
---@class liv.std.cursor
---@field hide fun() make the cursor invisible (idempotent; saves the prior state)
---@field show fun() restore the cursor to its pre-hide() appearance (idempotent)
local core = require("liv.core")

---@type liv.std.cursor
return (core.is_nvim and require("liv.std.cursor._nvim") or require("liv.std.cursor._vim"))(core)
