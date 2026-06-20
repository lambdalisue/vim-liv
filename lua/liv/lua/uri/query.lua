-- liv.lua.uri.query — the `k=v&k2=v2` query codec: encode_query/decode_query.
-- Keys and values are percent-coded, so this requires the percent leaf (and only
-- the percent leaf — never the barrel, which would re-pull parse/build).
local percent = require("liv.lua.uri.percent")

local M = {}

-- Encode a `{ key = value }` table into a "k=v&k2=v2" query string. A value may be
-- a scalar or an array of scalars; an array expands into repeated keys in order
-- ({ k = { "1", "2" } } → "k=1&k=2"). Keys and values are percent-encoded (so a
-- space becomes "%20", keeping the output RFC-clean). Keys are emitted in sorted
-- order, making the output deterministic and therefore testable.
---@param tbl table<string, string|string[]>
---@return string
function M.encode_query(tbl)
  local keys = {}
  for k in pairs(tbl) do
    keys[#keys + 1] = k
  end
  table.sort(keys)

  local pairs_out = {}
  for _, k in ipairs(keys) do
    local ek = percent.encode(k)
    local v = tbl[k]
    if type(v) == "table" then
      for _, item in ipairs(v) do
        pairs_out[#pairs_out + 1] = ek .. "=" .. percent.encode(item)
      end
    else
      pairs_out[#pairs_out + 1] = ek .. "=" .. percent.encode(v)
    end
  end

  return table.concat(pairs_out, "&")
end

-- Parse a "k=v&k2=v2" query string back into a table — the inverse of
-- encode_query. Keys and values are percent-decoded. A key without "=" ("a&b=2")
-- and an explicit empty value ("a=") both read as an empty-string value. A key
-- that appears more than once collects its values into an array, preserving
-- order; a key that appears once stays a scalar. An empty query yields an empty
-- table.
---@param str string
---@return table<string, string|string[]>
function M.decode_query(str)
  local out = {}
  if str == "" then
    return out
  end

  for piece in (str .. "&"):gmatch("(.-)&") do
    if piece ~= "" then
      local rawk, rawv = piece:match("^([^=]*)=(.*)$")
      if not rawk then
        rawk, rawv = piece, "" -- bare key, no "="
      end
      local key = percent.decode(rawk)
      local value = percent.decode(rawv)
      local existing = out[key]
      if existing == nil then
        out[key] = value
      elseif type(existing) == "table" then
        existing[#existing + 1] = value
      else
        out[key] = { existing, value }
      end
    end
  end

  return out
end

return M
