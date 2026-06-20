-- liv.std.text — display-width string operations (spec 0006). Editor-dependent
-- because measuring display columns needs a builtin: Lua's `#str` counts bytes,
-- not terminal columns (an East-Asian wide char is two columns). Both editors
-- ship strdisplaywidth() and it is the cross-editor display-width primitive we
-- pin to, so this is a single module with no backend split (like liv.std.sign /
-- liv.std.function): it behaves identically on Vim and Neovim. We deliberately do
-- NOT swap in Neovim's nvim_strwidth — it differs from strdisplaywidth on tabs
-- and 'ambiwidth', which would break cross-editor parity.
--
-- strdisplaywidth is bound as a marshaled function reference (vim.fn.*) — the
-- same shape the _nvim backends use for vim.api.*, so marshaling stays in core
-- and is never hand-rolled. `width` is the editor leaf; truncate/pad/align/wrap
-- delegate to the pure, editor-independent liv.lua.text algorithms with this real
-- width function injected (liv's "pure engine + editor leaf" pattern).
---@class liv.std.text
---@field width fun(str: string): integer
---@field truncate fun(str: string, max_width: integer, opts?: { ellipsis?: string, side?: string }): string
---@field pad fun(str: string, width: integer, opts?: { side?: string, fill?: string }): string
---@field align fun(str: string, width: integer, opts?: { side?: string, fill?: string }): string
---@field wrap fun(str: string, width: integer): string[]
local core = require("liv.core")
local pure = require("liv.lua.text")

local width = core.marshaled(vim.fn.strdisplaywidth)

local M = {}

-- Display columns occupied by `str` on a terminal (wide chars count as two).
---@param str string
---@return integer columns
function M.width(str)
  return width(str)
end

-- Truncate `str` to fit `max_width` display columns, marking truncation with an
-- ellipsis whose own width is counted (opts.ellipsis default "…"; opts.side
-- "right"|"left"|"center", default "right"). Slices on code-point boundaries.
---@param str string
---@param max_width integer
---@param opts? { ellipsis?: string, side?: string }
---@return string
function M.truncate(str, max_width, opts)
  return pure.truncate(str, max_width, opts, width)
end

-- Pad `str` with a fill character to reach `target_width` display columns
-- (opts.side "right"|"left"|"both", default "right"; opts.fill default " ").
-- Returns `str` unchanged when already at or beyond `target_width`.
---@param str string
---@param target_width integer
---@param opts? { side?: string, fill?: string }
---@return string
function M.pad(str, target_width, opts)
  return pure.pad(str, target_width, opts, width)
end

-- Align `str` within `target_width` display columns (opts.side "left"|"right"|
-- "center", default "left").
---@param str string
---@param target_width integer
---@param opts? { side?: string, fill?: string }
---@return string
function M.align(str, target_width, opts)
  return pure.align(str, target_width, opts, width)
end

-- Break `str` into lines each at most `target_width` display columns, breaking on
-- spaces where possible and hard-breaking long runs on code-point boundaries.
---@param str string
---@param target_width integer
---@return string[]
function M.wrap(str, target_width)
  return pure.wrap(str, target_width, width)
end

return M
