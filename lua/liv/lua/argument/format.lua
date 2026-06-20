-- liv.lua.argument.format — the format side of the command-argument family (spec
-- 0009). Pure Lua, editor-independent, deterministic, L1-testable. This is the
-- inverse of `liv.lua.argument.parse`: it rebuilds a command line from the
-- `opts`, `flags`, `rest` triple a parse produced.
--
-- It is the rarer direction (constructing a command line rather than interpreting
-- one), so it lives in its own leaf — a parse-only consumer never vendors it.
-- `format` does NOT call `parse`; the two sides are fully independent.

local M = {}

-- Quote a token for `format` so it survives a `split` round-trip. A token that is
-- empty or contains whitespace/quotes/backslash is wrapped in single quotes;
-- backslashes and single quotes inside are backslash-escaped (split treats `\` as
-- an escape even inside quotes, so a literal `\` must be doubled). Otherwise the
-- token is emitted bare.
---@param token string
---@return string
local function quote(token)
  if token == "" or token:find("[%s'\"\\]") then
    return "'" .. token:gsub("[\\']", "\\%0") .. "'"
  end
  return token
end

-- Emit one `key=value` pair sequence for an opt/flag entry, applying the repeat
-- expansion `parse` would collapse: an array expands into repeated keys; a boolean
-- `true` emits the bare flag (no `=`); a string emits `prefix..key=value`.
---@param out string[]
---@param prefix string `"++"` or `"--"`
---@param key string
---@param value string|boolean|(string|boolean)[]
local function emit(out, prefix, key, value)
  local items = type(value) == "table" and value or { value }
  for _, item in ipairs(items) do
    if item == true then
      out[#out + 1] = prefix .. key
    else
      out[#out + 1] = prefix .. key .. "=" .. tostring(item)
    end
  end
end

-- Sorted keys of a table, for deterministic output (mirrors uri.query.encode_query).
---@param tbl table
---@return string[]
local function sorted_keys(tbl)
  local keys = {}
  for k in pairs(tbl) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

-- Build a command line from `opts`, `flags`, `rest` — the inverse of `parse`. The
-- round-trip is SEMANTIC (`parse(format(o, f, r))` deep-equals `o, f, r`), not
-- byte-exact: key order is normalized (opts then flags, each sorted) and
-- positionals are quoted as needed. Short single-character boolean flags render as
-- `-x`; long flags render as `--name`.
---@param opts? table<string, string|boolean|(string|boolean)[]>
---@param flags? table<string, string|boolean|(string|boolean)[]>
---@param rest? string[]
---@return string
function M.format(opts, flags, rest)
  opts = opts or {}
  flags = flags or {}
  rest = rest or {}

  local out = {}

  for _, key in ipairs(sorted_keys(opts)) do
    emit(out, "++", key, opts[key])
  end

  for _, key in ipairs(sorted_keys(flags)) do
    local value = flags[key]
    -- A single-character boolean flag is a short flag (`-x`); anything else is a
    -- long flag (`--name` / `--name=value`).
    if value == true and #key == 1 then
      out[#out + 1] = "-" .. key
    else
      emit(out, "--", key, value)
    end
  end

  -- A positional that looks like a flag/opt/terminator (`-…`, `++…`, or `--`)
  -- would be re-parsed as one; emit a `--` terminator first so the whole `rest`
  -- survives the round-trip as positionals.
  local needs_terminator = false
  for _, token in ipairs(rest) do
    if token:sub(1, 1) == "-" or token:sub(1, 2) == "++" then
      needs_terminator = true
      break
    end
  end
  if needs_terminator then
    out[#out + 1] = "--"
  end

  for _, token in ipairs(rest) do
    out[#out + 1] = quote(token)
  end

  return table.concat(out, " ")
end

return M
