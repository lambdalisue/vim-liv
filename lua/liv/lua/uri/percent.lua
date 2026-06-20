-- liv.lua.uri.percent — byte-wise percent coding (RFC 3986 §2.1). The zero-
-- dependency, most-used concern of the URI codec: a consumer that needs only
-- encode/decode requires this leaf directly instead of the barrel, which would
-- also pull the parse/build and query machinery.
--
-- Operates on BYTES, so a multibyte UTF-8 character is coded as its constituent
-- bytes. Hex digits are uppercase, per RFC 3986 §2.1's recommendation.
local M = {}

-- RFC 3986 unreserved set: ALPHA / DIGIT / "-" / "." / "_" / "~". Everything else
-- is percent-encoded. The class is spelled out (not `%w`) so the membership is
-- explicit and locale-independent.
local UNRESERVED = "[^A-Za-z0-9%-._~]"

-- Percent-encode a string. Operates on BYTES, so a multibyte UTF-8 character is
-- encoded as its constituent bytes (e.g. "あ" → "%E3%81%82"). Hex digits are
-- uppercase, per RFC 3986 §2.1's recommendation. Space therefore becomes "%20"
-- (it is not unreserved), never "+".
---@param str string
---@return string
function M.encode(str)
  return (str:gsub(UNRESERVED, function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

-- Reverse percent-decoding: each "%XX" (XX = two hex digits) becomes the byte it
-- names. An incomplete or invalid escape ("%", "%2", "%zz") is left LITERAL
-- rather than raising — the pattern only matches a well-formed `%` + two hex
-- digits, so malformed input passes through untouched.
---@param str string
---@return string
function M.decode(str)
  return (str:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

return M
