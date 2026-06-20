-- liv.lua.base64.decode — Base64 decoder half (RFC 4648). Editor-independent and
-- L1-testable. Binary-safe: every byte 0x00..0xFF round-trips. Split from the
-- encoder so a decode-only consumer never vendors the encode tables/logic. The
-- same decode_with serves both alphabets via per-alphabet decode maps.
--
-- The unpacking is done with plain arithmetic (% and floor); the compat bit shim
-- is not needed because base64 is pure positional radix-64.
local tables = require("liv.lua.base64._tables")

local byte = string.byte
local char = string.char
local concat = table.concat
local floor = math.floor

-- Only the decode halves of each alphabet are kept here (second return value).
local _, STD_DEC = tables.build_tables(tables.STD_CHARS)
local _, URL_DEC = tables.build_tables(tables.URL_CHARS)

---@class liv.lua.base64.decode
local M = {}

-- Decode `s` against `dec`. ASCII whitespace and `=` padding are skipped; any
-- other character outside the alphabet raises a module-prefixed error.
local function decode_with(s, dec)
  local out = {}
  local acc, bits = 0, 0
  local n = #s
  for i = 1, n do
    local b = byte(s, i)
    if b == 61 then
      -- '=' padding: stop consuming significant data.
      break
    elseif b ~= 32 and b ~= 9 and b ~= 10 and b ~= 13 and b ~= 12 then
      -- a non-whitespace byte (ASCII whitespace — space, tab, LF, CR, FF — is skipped)
      local v = dec[b]
      if v == nil then
        error("liv.lua.base64: invalid character in input: " .. string.format("0x%02X", b))
      end
      acc = acc * 64 + v
      bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        local shift = 2 ^ bits
        out[#out + 1] = char(floor(acc / shift) % 256)
        acc = acc % shift
      end
    end
  end
  return concat(out)
end

-- Decode standard Base64 text. ASCII whitespace is ignored; a character outside
-- the alphabet raises an error. Missing `=` padding is tolerated.
---@param s string the Base64 text to decode
---@return string decoded the original bytes
function M.decode(s)
  return decode_with(s, STD_DEC)
end

-- Decode URL/filename-safe Base64 text. Accepts both unpadded (as emitted by
-- `encode_url`) and `=`-padded input. ASCII whitespace is ignored.
---@param s string the URL-safe Base64 text to decode
---@return string decoded the original bytes
function M.decode_url(s)
  return decode_with(s, URL_DEC)
end

return M
