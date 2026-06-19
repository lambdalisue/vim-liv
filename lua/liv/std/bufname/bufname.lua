-- Pure buffer-name codec for the denops/std `bufname` wire form:
--
--   scheme://expr[;k=v&k=v...][#fragment]
--
-- `format(bufname) -> string` and `parse(string) -> bufname` round-trip on the
-- object side: `parse(format(x))` reconstructs `x`. (The string side only
-- round-trips for canonical strings, since param order and encoding are
-- normalized on `format`.)
--
-- Percent-encoding follows nvim-aibo's fixed-table approach: `%` is encoded
-- first and decoded last so an already-`%XX`-looking expr survives. `expr`
-- additionally escapes Windows-unsafe characters; `expr`, param keys, and param
-- values each escape the structural delimiters that would otherwise mis-split a
-- parse (`;`, `#`, `&`, `=`).
local M = {}

---@class liv.std.bufname.Bufname
---@field scheme string Alphabetic-only scheme (no `://`).
---@field expr string Opaque expression (e.g. a path); percent-decoded.
---@field params? table<string, string|string[]> Query params; repeated keys decode to a list.
---@field fragment? string Optional fragment (e.g. a filetype hint); percent-decoded.

-- Characters escaped in `expr`: `%` first (so decode is unambiguous), the
-- Windows-unsafe set, and the structural delimiters that bound expr.
-- Each rule is `{ lua_pattern, literal_replacement }`. The replacement is
-- returned from the gsub function form, so it is taken verbatim (no `%`
-- escaping); only the pattern follows Lua-pattern rules.
local EXPR_ENCODE = {
  { "%%", "%25" }, -- `%` first
  { '"', "%22" },
  { "<", "%3C" },
  { ">", "%3E" },
  { "|", "%7C" },
  { "%?", "%3F" },
  { "%*", "%2A" },
  { ";", "%3B" },
  { "#", "%23" },
}

-- Characters escaped in param keys/values: `%` first, then the delimiters that
-- separate params from each other (`&`), key from value (`=`), and params from
-- expr/fragment (`;`, `#`).
local PARAM_ENCODE = {
  { "%%", "%25" }, -- `%` first
  { "&", "%26" },
  { "=", "%3D" },
  { ";", "%3B" },
  { "#", "%23" },
}

-- Reverse table shared by both decoders: `%` (`%25`) must be applied LAST so an
-- expr like `%3C` (literal text encoded as `%253C`) decodes back to `%3C` and
-- not to `<`.
local DECODE = {
  { "%%22", '"' },
  { "%%3C", "<" },
  { "%%3E", ">" },
  { "%%7C", "|" },
  { "%%3F", "?" },
  { "%%2A", "*" },
  { "%%26", "&" },
  { "%%3D", "=" },
  { "%%3B", ";" },
  { "%%23", "#" },
  { "%%25", "%" }, -- `%` last
}

local function apply(s, rules)
  for _, rule in ipairs(rules) do
    local replacement = rule[2]
    s = s:gsub(rule[1], function()
      return replacement
    end)
  end
  return s
end

local function encode_expr(s)
  return apply(s, EXPR_ENCODE)
end

local function encode_param(s)
  return apply(s, PARAM_ENCODE)
end

local function decode(s)
  return apply(s, DECODE)
end

local function is_scheme(scheme)
  return type(scheme) == "string" and scheme:match("^%a+$") ~= nil
end

---Format a bufname object into its wire string. Param keys are sorted for a
---deterministic result; multi-value keys keep their array order. Raises on a
---non-alphabetic scheme.
---@param bufname liv.std.bufname.Bufname
---@return string
function M.format(bufname)
  if not is_scheme(bufname.scheme) then
    error("bufname.format: scheme must be alphabetic, got " .. tostring(bufname.scheme))
  end

  local result = bufname.scheme .. "://" .. encode_expr(bufname.expr or "")

  local params = bufname.params
  if params then
    local keys = {}
    for key in pairs(params) do
      table.insert(keys, key)
    end
    table.sort(keys)

    local pairs_out = {}
    for _, key in ipairs(keys) do
      local value = params[key]
      local enc_key = encode_param(key)
      if type(value) == "table" then
        for _, item in ipairs(value) do
          table.insert(pairs_out, enc_key .. "=" .. encode_param(item))
        end
      else
        table.insert(pairs_out, enc_key .. "=" .. encode_param(value))
      end
    end
    if #pairs_out > 0 then
      result = result .. ";" .. table.concat(pairs_out, "&")
    end
  end

  if bufname.fragment then
    result = result .. "#" .. encode_expr(bufname.fragment)
  end

  return result
end

---Parse a wire string into a bufname object. Raises on a missing `://`
---separator or a non-alphabetic scheme.
---@param str string
---@return liv.std.bufname.Bufname
function M.parse(str)
  local scheme, rest = str:match("^([^:]*)://(.*)$")
  if not scheme then
    error("bufname.parse: missing '://' separator in " .. tostring(str))
  end
  if not is_scheme(scheme) then
    error("bufname.parse: scheme must be alphabetic, got " .. tostring(scheme))
  end

  local fragment
  local hash = rest:find("#", 1, true)
  if hash then
    fragment = decode(rest:sub(hash + 1))
    rest = rest:sub(1, hash - 1)
  end

  local query
  local semi = rest:find(";", 1, true)
  if semi then
    query = rest:sub(semi + 1)
    rest = rest:sub(1, semi - 1)
  end

  local result = { scheme = scheme, expr = decode(rest) }

  if query and query ~= "" then
    local params = {}
    for pair in query:gmatch("[^&]+") do
      local key, value = pair:match("^([^=]*)=(.*)$")
      if not key then
        key, value = pair, ""
      end
      key = decode(key)
      value = decode(value)
      local existing = params[key]
      if existing == nil then
        params[key] = value
      elseif type(existing) == "table" then
        table.insert(existing, value)
      else
        params[key] = { existing, value }
      end
    end
    result.params = params
  end

  result.fragment = fragment
  return result
end

return M
