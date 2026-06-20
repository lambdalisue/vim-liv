-- liv.lua.uri.url — the generic RFC 3986 split and its inverse: parse/build.
-- Pure, zero-dependency. Components are kept RAW — `parse` does NOT percent-
-- decode them and `build` does NOT percent-encode them — so a URI that is
-- already a valid wire form round-trips through parse/build unchanged, and the
-- percent codec stays a separate, deliberate step the caller composes (e.g.
-- query.decode_query(parse(s).query)). That is why this leaf requires neither
-- liv.lua.uri.percent nor liv.lua.uri.query.
local M = {}

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

return M
