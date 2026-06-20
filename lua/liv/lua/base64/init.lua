-- liv.lua.base64 — pure-Lua Base64 codec (RFC 4648). Editor-independent and
-- L1-testable. Binary-safe: every byte 0x00..0xFF round-trips, so it is safe for
-- arbitrary data (e.g. hashing input, embedded image bytes), not just text.
--
-- Two alphabets are exposed:
--   * standard (`encode`/`decode`)     — `+` and `/`, `=` padding.
--   * URL/filename-safe (`encode_url`/`decode_url`) — `-` and `_` (RFC 4648 §5).
--
-- The family is split into independent leaves so an encode-only consumer never
-- vendors the decoder (and vice versa):
--   * liv.lua.base64.encode — encode / encode_url.
--   * liv.lua.base64.decode — decode / decode_url.
-- Both share the internal liv.lua.base64._tables alphabet helper. This barrel
-- re-exposes the historical flat API (`encode`/`decode`/`encode_url`/
-- `decode_url`) for back-compat; the leaves are an additive split, not a breaking
-- move. The two sides are fully independent (encode never calls decode and vice
-- versa), so each can be required on its own without dragging the other in.
---@class liv.lua.base64
---@field encode fun(s: string): string
---@field decode fun(s: string): string
---@field encode_url fun(s: string): string
---@field decode_url fun(s: string): string
local encode = require("liv.lua.base64.encode")
local decode = require("liv.lua.base64.decode")

local M = {}
M.encode = encode.encode
M.encode_url = encode.encode_url
M.decode = decode.decode
M.decode_url = decode.decode_url
return M
