-- liv.std.json Vim backend: bind Vim builtins as marshaled function references
-- (vim.fn.*) — the same shape the _nvim backend uses for vim.api.*, so marshaling
-- stays in core and is never hand-rolled. Vim's json_encode is already compact,
-- matching Neovim's vim.json. Editor-dependent because it routes through the
-- editor's native JSON, which differs observably from a pure-Lua impl: a correct,
-- fast JSON (number formatting, escaping, NIL/empty-container handling consistent
-- with marshaling) is heavy to reimplement, and json_encode/json_decode agree
-- with marshaling.
return function(core)
  local fn = vim.fn
  local json_encode = core.marshaled(fn.json_encode)
  local json_decode = core.marshaled(fn.json_decode)

  local M = {}

  ---@param value any
  ---@return string json
  function M.encode(value)
    return json_encode(value)
  end

  ---@param json string
  ---@return any value
  function M.decode(json)
    return json_decode(json)
  end

  return M
end
