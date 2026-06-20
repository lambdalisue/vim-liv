-- liv.lua.uri — RFC 3986-shaped URI codec (spec 0006). Pure Lua, editor-
-- independent, deterministic, L1-testable. Lua ships no URI parsing or
-- percent-coding, so this owns liv's own vocabulary for it: parse/build (the
-- generic split and its inverse), encode/decode (byte-wise percent coding), and
-- encode_query/decode_query (the `k=v&...` form). The names are liv's own — this
-- is deliberately NOT the JS `URL`/`URLSearchParams` shape.
--
-- Components are kept RAW: `parse` does NOT percent-decode them, and `build` does
-- NOT percent-encode them. Decoding is a separate, deliberate step the caller
-- composes (e.g. `decode_query(parse(s).query)`), so a URI that is already a
-- valid wire form round-trips through `parse`/`build` unchanged.
--
-- This is the barrel: it requires the three concern leaves and re-exposes their
-- flat API unchanged, so require("liv.lua.uri") behaves exactly as before. A
-- consumer that needs only one concern requires that leaf directly instead —
-- e.g. require("liv.lua.uri.percent") pulls neither parse/build nor the query
-- codec.
--   * liv.lua.uri.percent — encode / decode (byte-wise percent coding)
--   * liv.lua.uri.url     — parse / build (generic RFC 3986 split + inverse)
--   * liv.lua.uri.query   — encode_query / decode_query (requires the percent leaf)
local percent = require("liv.lua.uri.percent")
local url = require("liv.lua.uri.url")
local query = require("liv.lua.uri.query")

---@class liv.lua.uri
local M = {}

M.encode = percent.encode
M.decode = percent.decode

M.parse = url.parse
M.build = url.build

M.encode_query = query.encode_query
M.decode_query = query.decode_query

return M
