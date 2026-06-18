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
---@class liv.std.autocmd
---@field on fun(events: string|string[], opts?: liv.std.autocmd.opts, handler: fun(ctx: liv.std.autocmd.ctx)): liv.std.autocmd.sub
---@field trigger fun(name: string)
local core = require("liv.core")

local backend = (core.is_nvim and require("liv.std.autocmd._nvim") or require("liv.std.autocmd._vim"))(core)

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

return M
