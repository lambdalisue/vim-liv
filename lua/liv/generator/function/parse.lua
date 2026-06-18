-- liv.generator.function.parse — extract function definitions from a Vim/Neovim
-- builtin.txt (pure Lua). Following @denops/std: signatures + names come from the
-- `*name()*` tag lines (present in BOTH editors), and the return type comes from
-- the Vim-style function-list table (`name(args)<TAB>TYPE<TAB>desc`, which Neovim
-- does not have). A tagged function with no table entry gets return type `any`.
-- Returns { name, params = {{name, optional}}, rettype } (Lua-mapped); arity
-- variants are separate entries.

local M = {}

-- Vim return types, longest first so "Float or Number" wins over "Float"/"Number".
local TYPE_ORDER = {
  "Float or Number",
  "Number", "String", "Float", "List", "Dict", "Funcref",
  "Blob", "Job", "Channel", "Boolean", "Bool", "none", "any",
}
local LUATYPE = {
  ["Float or Number"] = "number",
  Number = "integer",
  Float = "number",
  String = "string",
  List = "any[]",
  Dict = "table<string, any>",
  Boolean = "boolean",
  Bool = "boolean",
  Funcref = "any",
  Blob = "any",
  Job = "any",
  Channel = "any",
  none = "nil",
  any = "any",
}

local function parse_params(s)
  local params = {}
  local bracket = s:find("%[")
  local required = bracket and s:sub(1, bracket - 1) or s
  local optional = bracket and s:sub(bracket) or ""
  for name in required:gmatch("{([%w_]+)}") do
    params[#params + 1] = { name = name, optional = false }
  end
  for name in optional:gmatch("{([%w_]+)}") do
    params[#params + 1] = { name = name, optional = true }
  end
  return params
end

local function rettype_of(rest)
  for _, t in ipairs(TYPE_ORDER) do
    if rest:sub(1, #t) == t then
      local nxt = rest:sub(#t + 1, #t + 1)
      if nxt == "" or nxt:match("%s") then
        return LUATYPE[t]
      end
    end
  end
  return nil
end

-- Return types from the function-list table: name -> luatype (last arity wins).
local function list_rettypes(lines)
  local map = {}
  for _, line in ipairs(lines) do
    local name, _params, rest = line:match("^([%a_][%w_]*)%((.-)%)%s+(%S.*)$")
    if name then
      local rt = rettype_of(rest)
      if rt then
        map[name] = rt
      end
    end
  end
  return map
end

-- A function is *defined* where a `*name()*` tag sits at the end of a line; its
-- signature is the `name(args)` line nearest that tag. Using nearest (rather than
-- same-line) handles Vim's layout where a preceding example's `<` pushes the tag
-- onto its own line and the signature onto the next -- and ignores the far-away
-- function-list table rows. (More robust than @denops/std's fixed block window.)
local function tag_signatures(lines)
  local all_sigs = {}
  for i, line in ipairs(lines) do
    local name, args = line:match("^([%a_][%w_]*)%((.-)%)")
    if name then
      all_sigs[name] = all_sigs[name] or {}
      all_sigs[name][#all_sigs[name] + 1] = { line = i, args = args }
    end
  end

  local sigs, order = {}, {}
  for i, line in ipairs(lines) do
    local tag = line:match("%*([%a_][%w_]*)%(%)%*%s*$")
    if tag and all_sigs[tag] then
      local best, best_d
      for _, s in ipairs(all_sigs[tag]) do
        local d = math.abs(s.line - i)
        if not best_d or d < best_d then
          best, best_d = s, d
        end
      end
      if not sigs[tag] then
        sigs[tag] = {}
        order[#order + 1] = tag
      end
      sigs[tag][#sigs[tag] + 1] = best.args
    end
  end
  return sigs, order
end

-- A parsed function parameter.
---@class liv.generator.function.Param
---@field name string Parameter name.
---@field optional boolean Whether the parameter is optional.

-- A parsed function entry (one per arity variant).
---@class liv.generator.function.Entry
---@field name string Function name.
---@field params liv.generator.function.Param[] Function parameters.
---@field rettype string Lua-mapped return type.

---@param content string The `builtin.txt` document text.
---@return liv.generator.function.Entry[] entries Parsed function entries.
function M.parse(content)
  local lines = {}
  for line in (content .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end

  local rettypes = list_rettypes(lines)
  local sigs, order = tag_signatures(lines)

  local entries = {}
  for _, name in ipairs(order) do
    local rt = rettypes[name] or "any"
    for _, args in ipairs(sigs[name]) do
      entries[#entries + 1] = {
        name = name,
        params = parse_params(args),
        rettype = rt,
      }
    end
  end
  return entries
end

return setmetatable(M, {
  __call = function(_, content)
    return M.parse(content)
  end,
})
