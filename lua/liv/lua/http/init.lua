-- liv.lua.http — pure HTTP message helpers (spec 0006, note §18.2). Editor-
-- independent and L1-testable; it parses bytes, it does not do transport (that is
-- liv.std.fetch, which delegates TLS to curl/wget). parse_response reads a
-- response as emitted by `curl -i`: a status line, headers, a blank line, then the
-- body. With redirects (`curl -L`) the output carries one header block per hop;
-- the FINAL block — the one immediately before the body — is the one returned.
local M = {}

-- Parse one "HTTP/x.y NNN ...\r\nHeader: v\r\n..." block (no trailing CRLFCRLF).
local function parse_block(block)
  local headers = {}
  local status
  local first = true
  for line in (block .. "\r\n"):gmatch("(.-)\r\n") do
    if first then
      status = tonumber(line:match("^HTTP/%S+%s+(%d+)"))
      first = false
    else
      local k, v = line:match("^([^:]+):%s*(.*)$")
      if k then
        headers[k:lower()] = v -- header names are case-insensitive
      end
    end
  end
  return status, headers
end

-- status is nil when no `HTTP/` block parses (e.g. a body-only / non-HTTP
-- response); the caller decides how to degrade (liv.std.fetch floors it to 200
-- for a successful transfer, mirroring the wget path).
---@param raw string the raw response bytes (headers + body)
---@return { status: integer?, headers: table<string,string>, body: string }
function M.parse_response(raw)
  local pos = 1
  local status, headers = nil, {}
  -- Consume successive header blocks; the body is whatever follows the last one.
  while raw:sub(pos, pos + 4) == "HTTP/" do
    local sep = raw:find("\r\n\r\n", pos, true)
    if not sep then
      break
    end
    status, headers = parse_block(raw:sub(pos, sep - 1))
    pos = sep + 4
  end
  return { status = status, headers = headers, body = raw:sub(pos) }
end

-- Parse the response headers `wget -S` writes to stderr. GNU wget indents each
-- response-header line by exactly two spaces (progress lines are not indented);
-- following redirects yields one indented block per hop, so the final `HTTP/...`
-- group wins. Returns nil status when no header block is present (e.g. busybox
-- wget without -S support), so the caller can fall back to a degraded GET.
-- Returns the same `{ status, headers }` shape as parse_response (minus body,
-- which wget writes to stdout), so the module has one parser return shape.
---@param stderr string wget's captured stderr
---@return { status: integer?, headers: table<string,string> }
function M.parse_wget_stderr(stderr)
  local lines = {}
  for line in (stderr .. "\n"):gmatch("(.-)\n") do
    local stripped = line:match("^  (.*)$") -- exactly two leading spaces
    if stripped then
      lines[#lines + 1] = stripped
    end
  end
  local start
  for i = #lines, 1, -1 do
    if lines[i]:match("^HTTP/") then
      start = i
      break
    end
  end
  if not start then
    return { status = nil, headers = {} }
  end
  local block = {}
  for i = start, #lines do
    block[#block + 1] = lines[i]
  end
  local status, headers = parse_block(table.concat(block, "\r\n"))
  return { status = status, headers = headers }
end

return M
