-- liv.std.mapping — key mappings (spec 0006). Editor-dependent; selects a backend
-- once at import. `set(modes, lhs, opts?, rhs)` maps `lhs` (in each mode) to `rhs`
-- and returns a subscription whose `off()` removes the mapping; `del(modes, lhs,
-- opts?)` is a thin convenience removal.
--
-- `opts` is optional: `set(modes, lhs, rhs)` omits it (detected because the
-- opts-position argument is then the string/function action, never a table).
--
-- `rhs` is either a string of keys or a plain Lua function. A function rhs runs
-- on both editors (Neovim binds it as a native callback; Vim routes it through
-- the Vim 9 dispatch) and is called as `handler(ctx)` with the count/register/mode
-- in effect. With `opts.expr`, the function's return string is fed back as the
-- keys to type (so the handler MUST return a string); key-notation in that string
-- (e.g. "<CR>") is translated to real keys on BOTH editors. Without `expr` the
-- return is ignored. `opts.buffer` scopes the mapping to the current buffer.
---@class liv.std.mapping.ctx
---@field count integer the count typed before the mapping (0 when none)
---@field register string the register named before the mapping ("" when none)
---@field mode string the mode this mapping was declared for (e.g. "n", "i")
---@class liv.std.mapping.opts
---@field noremap? boolean do not remap the rhs (default true)
---@field silent? boolean do not echo the mapping
---@field expr? boolean treat a function/string rhs as producing the keys to type
---@field nowait? boolean do not wait for further keys that could extend `lhs`
---@field buffer? boolean scope the mapping to the current buffer
---@class liv.std.mapping.sub
---@field off fun() remove this mapping (idempotent)
---@class liv.std.mapping
---@field set fun(modes: string|string[], lhs: string, opts?: liv.std.mapping.opts, rhs: string|fun(ctx: liv.std.mapping.ctx): string?): liv.std.mapping.sub
---@field del fun(modes: string|string[], lhs: string, opts?: { buffer?: boolean })
local core = require("liv.core")

local backend = (core.is_nvim and require("liv.std.mapping._nvim") or require("liv.std.mapping._vim"))(core)

---@class liv.std.mapping
local M = {}

---@param modes string|string[]
---@param lhs string
---@param opts? liv.std.mapping.opts the optional opts, or the rhs when omitted
---@param rhs? string|fun(ctx: liv.std.mapping.ctx): string?
---@return liv.std.mapping.sub
function M.set(modes, lhs, opts, rhs)
  -- opts is optional and lives second-to-last. When omitted, the opts-position
  -- argument is the rhs (a string or function), never a table; shift it.
  if rhs == nil and type(opts) ~= "table" then
    opts, rhs = {}, opts
  end
  return backend.set(modes, lhs, opts or {}, rhs)
end

---@param modes string|string[]
---@param lhs string
---@param opts? { buffer?: boolean }
function M.del(modes, lhs, opts)
  return backend.del(modes, lhs, opts)
end

return M
