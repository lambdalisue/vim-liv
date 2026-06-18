-- liv.std.json Neovim backend: native vim.json (compact output, no spaces),
-- bound through core.marshaled so NIL / empty containers / lists / dicts cross
-- correctly. Editor-dependent because it routes through the editor's native JSON,
-- which differs observably from a pure-Lua impl: a correct, fast JSON (number
-- formatting, escaping, NIL/empty-container handling consistent with marshaling)
-- is heavy to reimplement, and the editor's encoder agrees with marshaling.
return function(core)
  local encode = core.marshaled(vim.json.encode)
  local decode = core.marshaled(vim.json.decode)

  local M = {}

  ---@param value any
  ---@return string json
  function M.encode(value)
    return encode(value)
  end

  ---@param json string
  ---@return any value
  function M.decode(json)
    return decode(json)
  end

  return M
end
