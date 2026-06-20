-- liv.lua.text.coerce — argument/content coercion helpers (spec 0006). The zero-
-- dependency coercion concern of the text module: normalize display content into
-- a list of lines, and coerce a string-or-list argument into a plain list to
-- iterate. A consumer that needs only coercion (e.g. the popup/mapping backends,
-- which take `content`/`modes` as either a scalar or a list) requires this leaf
-- directly instead of the barrel, which would also pull the display-width group.
--
-- Editor-independent: these carry no editor access, so the editor-dependent
-- backends share one implementation instead of each hand-rolling a byte-identical
-- copy. Deterministic pure Lua, L1-testable, identical on every host.
local M = {}

-- Normalize display content into a list of lines: a list is returned as-is; a
-- string is split on "\n" (a trailing newline yields a trailing empty line, and
-- an empty string yields a single empty line, matching how the editors render a
-- single blank row).
---@param content string|string[]
---@return string[] lines
function M.lines(content)
  if type(content) == "table" then
    return content
  end
  local out = {}
  for line in (content .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = line
  end
  return out
end

-- Coerce a string-or-list argument into a plain list to iterate. A list is
-- returned as-is; a scalar (e.g. a single mode "n") is wrapped into a
-- one-element list. Used to accept `modes` as either "n" or { "n", "i" }.
---@generic T
---@param value T|T[]
---@return T[] list
function M.aslist(value)
  if type(value) == "table" then
    return value
  end
  return { value }
end

return M
