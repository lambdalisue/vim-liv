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
-- Read-back info for an existing mapping. liv's own vocabulary, mapped from the
-- editor's maparg dict (raw editor keys are not exposed). A Lua-function rhs is
-- reported as the marker string "<Lua function>" (its real body is not a string);
-- a string rhs is reported verbatim. The flag fields are Lua booleans.
---@class liv.std.mapping.info
---@field lhs string the left-hand side as typed
---@field rhs string the right-hand side, or "<Lua function>" for a function rhs
---@field mode string the mode this mapping belongs to
---@field noremap boolean the rhs is not remapped
---@field silent boolean the mapping does not echo
---@field expr boolean the rhs is an expression producing the keys
---@field nowait boolean the mapping does not wait for a longer lhs
---@field buffer boolean the mapping is buffer-local
---@class liv.std.mapping.list.opts
---@field mode? string only mappings declared for this mode
---@field prefix? string only mappings whose lhs starts with this string
---@class liv.std.mapping
---@field set fun(modes: string|string[], lhs: string, opts?: liv.std.mapping.opts, rhs: string|fun(ctx: liv.std.mapping.ctx): string?): liv.std.mapping.sub
---@field del fun(modes: string|string[], lhs: string, opts?: { buffer?: boolean })
---@field get fun(modes: string|string[], lhs: string, opts?: { buffer?: boolean }): liv.std.mapping.info?
---@field list fun(opts?: liv.std.mapping.list.opts): liv.std.mapping.info[]
local core = require("liv.core")

local backend = (core.is_nvim and require("liv.std.mapping._nvim") or require(
  "liv.std.mapping._vim"
))(core)

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

-- Information about an existing mapping for a single mode, or nil if `lhs` is not
-- mapped there. When `modes` is a list its first element is used (a mapping is
-- queried one mode at a time). `opts.buffer` queries the buffer-local mapping.
---@param modes string|string[]
---@param lhs string
---@param opts? { buffer?: boolean }
---@return liv.std.mapping.info?
function M.get(modes, lhs, opts)
  return backend.get(modes, lhs, opts or {})
end

-- All mappings, optionally filtered by `opts.mode` and/or `opts.prefix` (lhs
-- starts-with). Returns an array of info tables (empty when none match).
---@param opts? liv.std.mapping.list.opts
---@return liv.std.mapping.info[]
function M.list(opts)
  return backend.list(opts or {})
end

return M
