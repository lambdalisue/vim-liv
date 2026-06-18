-- liv.generator.option.parse — extract option definitions from a Vim/Neovim
-- `runtime/doc/options.txt`. Pure Lua, editor-independent (a build-time tool, so
-- never vendored). Returns a list of { name, type, scope } where type is
-- "boolean"/"number"/"string" and scope is "global"/"buffer"/"window".
--
-- A block looks like:
--   'expandtab' 'et'<TAB>boolean<TAB>(default off)
--               local to buffer
--       In Insert mode: ...
-- The header line carries the (long) name, optional short name, and type; the
-- following indented line(s) carry the scope (absent => global).

local M = {}

-- The first whitespace-separated word of `rest` that is a type keyword, skipping
-- an optional leading 'short' name.
local function header_type(rest)
  local after_short = rest:match("^'[%a_][%w_]*'%s+(.*)") or rest
  return after_short:match("^(%a+)")
end

local function scope_of(lines, from)
  for j = from, math.min(from + 4, #lines) do
    local s = lines[j]
    if s:match("^'") then
      break -- next option block; no scope line seen
    elseif s:match("local to buffer") then
      return "buffer"
    elseif s:match("local to window") then
      return "window"
    elseif s:match("global") then
      return "global"
    end
  end
  return "global"
end

local TYPES = { boolean = true, number = true, string = true }

-- A parsed option definition.
---@class liv.generator.option.Def
---@field name string Option (long) name.
---@field type string Option type: "boolean"/"number"/"string".
---@field scope string Option scope: "global"/"buffer"/"window".

---@param content string The `options.txt` document text.
---@return liv.generator.option.Def[] options Parsed option definitions.
function M.parse(content)
  local lines = {}
  for line in (content .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end

  local options = {}
  for i, line in ipairs(lines) do
    local name, rest = line:match("^'([%a_][%w_]*)'%s+(.*)")
    if name then
      local typ = header_type(rest)
      if typ and TYPES[typ] then
        options[#options + 1] = {
          name = name,
          type = typ,
          scope = scope_of(lines, i + 1),
        }
      end
    end
  end
  return options
end

return setmetatable(M, {
  __call = function(_, content)
    return M.parse(content)
  end,
})
