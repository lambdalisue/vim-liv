-- liv.std.command — user commands (spec 0006). Editor-dependent; selects a
-- backend once at import. `define(name, opts?, handler)` registers a command that
-- calls handler(args) with the command's argument string and returns a
-- subscription whose `off()` deletes it; `remove(name)` is a thin convenience
-- removal. Neovim uses a native Lua callback; Vim routes through the Vim 9
-- dispatch.
--
-- `opts` is optional: `define(name, handler)` omits it (detected because the
-- opts-position argument is then the handler function, never a table).
--
-- opts.complete is an optional custom completion function. It is called with
-- (arglead, cmdline, cursorpos) and must return a string[] of candidates --
-- the cross-editor equivalent of `:command -complete=customlist`. On Neovim it
-- is wired as a Lua `complete` callback; on Vim a `customlist` funcref bridges
-- back to it through the Vim 9 dispatch.
---@class liv.std.command.opts
---@field nargs? string|integer the command's argument arity (default "*")
---@field complete? fun(arglead: string, cmdline: string, cursorpos: integer): string[]
---@class liv.std.command.sub
---@field off fun() delete this command (idempotent)
---@class liv.std.command
---@field define fun(name: string, opts?: liv.std.command.opts, handler: fun(args: string)): liv.std.command.sub
---@field remove fun(name: string)
local core = require("liv.core")

local backend = (core.is_nvim and require("liv.std.command._nvim") or require("liv.std.command._vim"))(core)

---@class liv.std.command
local M = {}

---@param name string
---@param opts? liv.std.command.opts the optional opts, or the handler when omitted
---@param handler? fun(args: string)
---@return liv.std.command.sub
function M.define(name, opts, handler)
  -- opts is optional and lives second-to-last. When omitted, the opts-position
  -- argument is the handler (a function), never a table; shift it.
  if handler == nil and type(opts) ~= "table" then
    opts, handler = {}, opts
  end
  return backend.define(name, opts or {}, handler)
end

---@param name string
function M.remove(name)
  return backend.remove(name)
end

return M
