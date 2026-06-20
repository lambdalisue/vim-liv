-- liv.std.ui — user interaction (spec 0006). Editor-dependent; selects a backend
-- once at import. select/prompt are callback-based so both editors share one
-- model: Neovim is natively asynchronous (vim.ui.select / vim.ui.input), Vim
-- blocks until the user answers and then invokes the handler synchronously. The
-- handler receives nil when the user cancels. notify shows a message at a
-- severity level ("info"/"warn"/"error") — liv's own vocabulary, mapped to each
-- editor's mechanism.
--
-- `opts` is optional: `select(items, handler)` / `prompt(handler)` omit it
-- (detected because the opts-position argument is then the handler function,
-- never a table).
--
-- `prompt` accepts an optional `opts.completion`: a `fun(lead) -> string[]`
-- returning completion candidates for the current input lead. It is Vim-strong /
-- Neovim-best-effort. On Vim it is wired to a customlist completion function via
-- the callback dispatch and drives input()'s {completion} argument; because Vim's
-- completing input() carries no cancel sentinel, supplying completion makes cancel
-- (Esc) yield "" instead of nil (the non-completion path keeps cancel -> nil). On
-- Neovim a Lua completion function cannot be honored by the default vim.ui.input
-- (its documented `completion` is a `-complete=` TYPE STRING, not a function, and
-- forwarding a Funcref to vim.fn.input raises E729), so completion simply does
-- nothing there; prompt itself always works on both editors regardless.
---@alias liv.std.ui.level "info"|"warn"|"error"
---@class liv.std.ui
---@field select fun(items: string[], opts?: { prompt?: string }, handler: fun(item: string?, index: integer?))
---@field prompt fun(opts?: { prompt?: string, default?: string, completion?: fun(lead: string): string[] }, handler: fun(text: string?))
---@field notify fun(msg: string, level?: liv.std.ui.level)
local core = require("liv.core")

local backend = (core.is_nvim and require("liv.std.ui._nvim") or require("liv.std.ui._vim"))(core)

---@class liv.std.ui
local M = {}

---@param items string[]
---@param opts? { prompt?: string } the optional opts, or the handler when omitted
---@param handler? fun(item: string?, index: integer?)
function M.select(items, opts, handler)
  if handler == nil and type(opts) ~= "table" then
    opts, handler = {}, opts
  end
  return backend.select(items, opts or {}, handler)
end

---@param opts? { prompt?: string, default?: string, completion?: fun(lead: string): string[] } the optional opts, or the handler when omitted
---@param handler? fun(text: string?)
function M.prompt(opts, handler)
  if handler == nil and type(opts) ~= "table" then
    opts, handler = {}, opts
  end
  return backend.prompt(opts or {}, handler)
end

---@param msg string
---@param level? liv.std.ui.level
function M.notify(msg, level)
  return backend.notify(msg, level)
end

return M
