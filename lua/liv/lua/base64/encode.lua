-- liv.lua.base64.encode — Base64 encoder half (RFC 4648). Editor-independent and
-- L1-testable. Binary-safe: every byte 0x00..0xFF round-trips. Split from the
-- decoder so an encode-only consumer never vendors the decode tables/logic.
--
-- The packing is done with plain arithmetic (% and floor) like the sibling
-- liv.lua.zlib reader; the compat bit shim is not needed here because base64 is
-- pure positional radix-64, which `math.floor` and `%` express directly.
local tables = require("liv.lua.base64._tables")

local byte = string.byte
local concat = table.concat
local floor = math.floor

-- Only the encode halves of each alphabet are kept here.
local STD_ENC = tables.build_tables(tables.STD_CHARS)
local URL_ENC = tables.build_tables(tables.URL_CHARS)

---@class liv.lua.base64.encode
local M = {}

-- Encode `s` against `enc`; emit `=` padding only when `pad` is true.
local function encode_with(s, enc, pad)
  local out = {}
  local n = #s
  local i = 1
  while i <= n do
    local b1 = byte(s, i)
    local b2 = byte(s, i + 1)
    local b3 = byte(s, i + 2)

    -- Pack up to three bytes into a 24-bit group, MSB-first.
    local triple = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
    local c1 = floor(triple / 262144) % 64
    local c2 = floor(triple / 4096) % 64
    local c3 = floor(triple / 64) % 64
    local c4 = triple % 64

    out[#out + 1] = enc[c1]
    out[#out + 1] = enc[c2]
    if b2 == nil then
      -- 1 leftover byte -> 2 chars + "==".
      if pad then
        out[#out + 1] = "="
        out[#out + 1] = "="
      end
    elseif b3 == nil then
      -- 2 leftover bytes -> 3 chars + "=".
      out[#out + 1] = enc[c3]
      if pad then
        out[#out + 1] = "="
      end
    else
      out[#out + 1] = enc[c3]
      out[#out + 1] = enc[c4]
    end
    i = i + 3
  end
  return concat(out)
end

-- Encode bytes to standard Base64 (RFC 4648 §4) with `=` padding.
---@param s string the bytes to encode
---@return string encoded the Base64 text (with `+`/`/`, `=`-padded)
function M.encode(s)
  return encode_with(s, STD_ENC, true)
end

-- Encode bytes to URL/filename-safe Base64 (RFC 4648 §5): `-` and `_`, and NO
-- trailing `=` padding (the common URL convention). Decode accepts either form.
---@param s string the bytes to encode
---@return string encoded the URL-safe Base64 text (unpadded)
function M.encode_url(s)
  return encode_with(s, URL_ENC, false)
end

return M
