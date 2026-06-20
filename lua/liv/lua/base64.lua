-- liv.lua.base64 — pure-Lua Base64 codec (RFC 4648). Editor-independent and
-- L1-testable. Binary-safe: every byte 0x00..0xFF round-trips, so it is safe for
-- arbitrary data (e.g. hashing input, embedded image bytes), not just text.
--
-- Two alphabets are exposed:
--   * standard (`encode`/`decode`)     — `+` and `/`, `=` padding.
--   * URL/filename-safe (`encode_url`/`decode_url`) — `-` and `_` (RFC 4648 §5).
--
-- The packing is done with plain arithmetic (% and floor) like the sibling
-- liv.lua.zlib reader; the compat bit shim is not needed here because base64 is
-- pure positional radix-64, which `math.floor` and `%` express directly.
local byte = string.byte
local char = string.char
local concat = table.concat
local floor = math.floor

---@class liv.lua.base64
local M = {}

local STD_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local URL_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

-- Build, once, the index->char encode table and the char-byte->index decode map
-- for a given 64-character alphabet.
local function build_tables(alphabet)
  local enc, dec = {}, {}
  for i = 1, 64 do
    local c = alphabet:sub(i, i)
    enc[i - 1] = c
    dec[byte(c)] = i - 1
  end
  return enc, dec
end

local STD_ENC, STD_DEC = build_tables(STD_CHARS)
local URL_ENC, URL_DEC = build_tables(URL_CHARS)

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

-- Encode bytes to standard Base64 (RFC 4648 §4) with `=` padding.
---@param s string the bytes to encode
---@return string encoded the Base64 text (with `+`/`/`, `=`-padded)
function M.encode(s)
  return encode_with(s, STD_ENC, true)
end

-- Decode standard Base64 text. ASCII whitespace is ignored; a character outside
-- the alphabet raises an error. Missing `=` padding is tolerated.
---@param s string the Base64 text to decode
---@return string decoded the original bytes
function M.decode(s)
  return decode_with(s, STD_DEC)
end

-- Encode bytes to URL/filename-safe Base64 (RFC 4648 §5): `-` and `_`, and NO
-- trailing `=` padding (the common URL convention). Decode accepts either form.
---@param s string the bytes to encode
---@return string encoded the URL-safe Base64 text (unpadded)
function M.encode_url(s)
  return encode_with(s, URL_ENC, false)
end

-- Decode URL/filename-safe Base64 text. Accepts both unpadded (as emitted by
-- `encode_url`) and `=`-padded input. ASCII whitespace is ignored.
---@param s string the URL-safe Base64 text to decode
---@return string decoded the original bytes
function M.decode_url(s)
  return decode_with(s, URL_DEC)
end

return M
