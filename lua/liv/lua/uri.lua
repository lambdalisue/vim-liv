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

-- Split the authority component ("[userinfo@]host[:port]") into its parts. Only
-- ever called for a real authority (i.e. when the URI had a "//"), so it does not
-- have to defend against a stray "@" that actually belongs to a path. The port is
-- gated to a trailing run of digits, which also leaves an IPv6 literal host
-- ("[::1]") intact instead of splitting on its inner colons.
---@param authority string
---@return string? userinfo, string host, integer? port
local function split_authority(authority)
  local userinfo, hostport = authority:match("^([^@]*)@(.*)$")
  if not userinfo then
    hostport = authority
  end
  local host, port = hostport:match("^(.-):(%d+)$")
  if host then
    return userinfo, host, tonumber(port)
  end
  return userinfo, hostport, nil
end

-- Decompose a URI into its generic RFC 3986 components. Fields are nil when the
-- component is absent; `port` is an integer when present. Components are returned
-- RAW (not percent-decoded). The split peels in a fixed order — fragment, query,
-- scheme, authority, path — because Lua patterns have no alternation, so the
-- single-regex Appendix-B approach is not portable here.
--
-- userinfo/host/port are populated ONLY when an authority is present (the URI had
-- "//" after the scheme). Without it (e.g. "mailto:foo@bar.com") the "@" stays in
-- the path and host/userinfo/port are nil.
---@param str string
---@return { scheme: string?, authority: string?, userinfo: string?, host: string?, port: integer?, path: string, query: string?, fragment: string? }
function M.parse(str)
  local rest = str
  local fragment, query, scheme, authority

  -- Fragment: everything after the first "#".
  local hash = rest:find("#", 1, true)
  if hash then
    fragment = rest:sub(hash + 1)
    rest = rest:sub(1, hash - 1)
  end

  -- Query: everything after the first "?".
  local q = rest:find("?", 1, true)
  if q then
    query = rest:sub(q + 1)
    rest = rest:sub(1, q - 1)
  end

  -- Scheme: a letter-led "scheme:" prefix. Anchored and letter-leading so a
  -- bare "host:port" path (e.g. "1.2.3.4:80") is not misread as a scheme.
  local s, srest = rest:match("^(%a[%w+.-]*):(.*)$")
  if s then
    scheme = s
    rest = srest
  end

  -- Authority: present only when the remainder starts with "//". It runs up to
  -- the next "/", "?" or "#" — but query/fragment are already peeled, so it runs
  -- up to the next "/" (or end of string).
  if rest:sub(1, 2) == "//" then
    local body = rest:sub(3)
    local slash = body:find("/", 1, true)
    if slash then
      authority = body:sub(1, slash - 1)
      rest = body:sub(slash)
    else
      authority = body
      rest = ""
    end
  end

  local userinfo, host, port
  if authority then
    userinfo, host, port = split_authority(authority)
  end

  return {
    scheme = scheme,
    authority = authority,
    userinfo = userinfo,
    host = host,
    port = port,
    path = rest,
    query = query,
    fragment = fragment,
  }
end

-- Assemble a URI string from the same shape `parse` returns — its inverse. The
-- authority is taken from the explicit `host`/`userinfo`/`port` components when
-- `host` is set; otherwise it falls back to the `authority` string. (parse emits
-- both, so this rule keeps the two round-trip directions consistent.) Components
-- are written RAW (no percent-encoding). Absent fields are simply omitted.
---@param parts { scheme: string?, authority: string?, userinfo: string?, host: string?, port: integer?, path: string?, query: string?, fragment: string? }
---@return string
function M.build(parts)
  local out = {}

  if parts.scheme then
    out[#out + 1] = parts.scheme
    out[#out + 1] = ":"
  end

  local authority
  if parts.host then
    authority = parts.host
    if parts.port then
      authority = authority .. ":" .. tostring(parts.port)
    end
    if parts.userinfo then
      authority = parts.userinfo .. "@" .. authority
    end
  else
    authority = parts.authority
  end
  if authority then
    out[#out + 1] = "//"
    out[#out + 1] = authority
  end

  out[#out + 1] = parts.path or ""

  if parts.query then
    out[#out + 1] = "?"
    out[#out + 1] = parts.query
  end

  if parts.fragment then
    out[#out + 1] = "#"
    out[#out + 1] = parts.fragment
  end

  return table.concat(out)
end

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
    local ek = M.encode(k)
    local v = tbl[k]
    if type(v) == "table" then
      for _, item in ipairs(v) do
        pairs_out[#pairs_out + 1] = ek .. "=" .. M.encode(item)
      end
    else
      pairs_out[#pairs_out + 1] = ek .. "=" .. M.encode(v)
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
      local key = M.decode(rawk)
      local value = M.decode(rawv)
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
