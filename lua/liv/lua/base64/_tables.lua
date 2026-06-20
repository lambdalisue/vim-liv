-- liv.lua.base64._tables — internal shared alphabet helper for the base64 family
-- (spec 0006). NOT a public contract: a consumer requires the encode or decode
-- leaf, never this directly. It lives apart only so the encode and decode leaves
-- share one definition of the two RFC 4648 alphabets and the table builder
-- without either leaf requiring the other (a leaf may depend on this internal
-- helper; it must never depend on the barrel).
local byte = string.byte

local M = {}

-- RFC 4648 §4 standard alphabet (`+` and `/`).
M.STD_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
-- RFC 4648 §5 URL/filename-safe alphabet (`-` and `_`).
M.URL_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

-- Build, once, the index->char encode table and the char-byte->index decode map
-- for a given 64-character alphabet. The caller keeps whichever half it needs.
---@param alphabet string a 64-character alphabet
---@return table<integer, string> enc index (0..63) -> character
---@return table<integer, integer> dec character byte -> index (0..63)
function M.build_tables(alphabet)
  local enc, dec = {}, {}
  for i = 1, 64 do
    local c = alphabet:sub(i, i)
    enc[i - 1] = c
    dec[byte(c)] = i - 1
  end
  return enc, dec
end

return M
