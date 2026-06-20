-- liv.std.autocmd — autocommands (spec 0006). Editor-dependent; selects a
-- backend once at import. `on(events, opts, handler)` runs `handler(ctx)` when any
-- of `events` fires (returning a subscription whose `off()` removes it);
-- `trigger(name)` fires a `User` autocommand so other code can react. The handler
-- is a plain Lua function on both editors — Neovim binds it as a native callback,
-- Vim routes it through the Vim 9 dispatch — and receives a context table.
---@class liv.std.autocmd.ctx
---@field buf integer the buffer the event fired for (0 when not buffer-bound)
---@field file string the matched file name (`<afile>`)
---@field match string the matched pattern value (`<amatch>`)
---@class liv.std.autocmd.opts
---@field pattern? string|string[] autocommand pattern(s) (default `*`)
---@field buffer? integer scope the autocommand to this buffer (mutually exclusive with pattern)
---@field group? string a named group to register under
---@field once? boolean remove the autocommand after it fires once
---@class liv.std.autocmd.sub
---@field off fun() remove this autocommand (idempotent)
-- Read-back info for one registered autocommand. liv's cross-editor shape, mapped
-- from each editor's native listing. `buffer` is the buffer number for a
-- buffer-local autocommand, else 0. `group` is the augroup the autocommand belongs
-- to (see note below: liv's `_vim` backend puts each subscription in its own
-- private augroup `<group>_<n>`, so the reported group differs between editors even
-- though the shape matches).
---@class liv.std.autocmd.info
---@field event string the event name (e.g. "User", "BufEnter")
---@field pattern string the autocommand pattern
---@field group string|nil the augroup the autocommand belongs to (nil if ungrouped)
---@field buffer integer the buffer for a buffer-local autocommand (0 otherwise)
---@class liv.std.autocmd.list.opts
---@field event? string|string[] only autocommands for this event (events)
---@field group? string only autocommands whose group starts with this name
---@field pattern? string only autocommands with this exact pattern
---@class liv.std.autocmd
---@field on fun(events: string|string[], opts?: liv.std.autocmd.opts, handler: fun(ctx: liv.std.autocmd.ctx)): liv.std.autocmd.sub
---@field trigger fun(name: string)
---@field list fun(opts?: liv.std.autocmd.list.opts): liv.std.autocmd.info[]
local core = require("liv.core")

local backend = (core.is_nvim and require("liv.std.autocmd._nvim") or require(
  "liv.std.autocmd._vim"
))(core)

---@class liv.std.autocmd
local M = {}

-- `on(events, opts?, handler)` runs `handler(ctx)` when any of `events` fires and
-- returns a subscription whose `off()` removes it (idempotent). `opts` is
-- optional: `on(events, handler)` omits it (detected because the opts-position
-- argument is then the handler function, never a table).
---@param events string|string[]
---@param opts? liv.std.autocmd.opts the optional opts, or the handler when omitted
---@param handler? fun(ctx: liv.std.autocmd.ctx)
---@return liv.std.autocmd.sub
function M.on(events, opts, handler)
  if handler == nil and type(opts) ~= "table" then
    opts, handler = {}, opts
  end
  return backend.on(events, opts or {}, handler)
end

---@param name string
function M.trigger(name)
  return backend.trigger(name)
end

-- All registered autocommands, optionally filtered by `opts.event`, `opts.group`
-- (the caller-supplied group name; matched against the actual augroup as a prefix
-- because the `_vim` backend prefixes a private suffix), and `opts.pattern` (exact).
-- Returns an array of info tables (empty when none match).
---@param opts? liv.std.autocmd.list.opts
---@return liv.std.autocmd.info[]
function M.list(opts)
  return backend.list(opts or {})
end

return M
