-- L1 unit test for liv.lua.http (spec 0006). Pure, no editor. Pins the response
-- parsing that liv.std.fetch relies on, including the redirect case (curl -L emits
-- one header block per hop; the final block wins).
local http = require("liv.lua.http")

describe("liv.lua.http.parse_response", function()
  it("parses status, headers, and body from a single block", function()
    local raw = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello"
    local r = http.parse_response(raw)
    assert.equal(200, r.status)
    assert.equal("text/plain", r.headers["content-type"])
    assert.equal("5", r.headers["content-length"])
    assert.equal("hello", r.body)
  end)

  it("lower-cases header names (case-insensitive)", function()
    local r = http.parse_response("HTTP/1.1 204 No Content\r\nX-Custom-Header: yes\r\n\r\n")
    assert.equal("yes", r.headers["x-custom-header"])
    assert.equal("", r.body)
  end)

  it("returns the final block after redirects (curl -L)", function()
    local raw = "HTTP/1.1 301 Moved\r\nLocation: http://x\r\n\r\n"
      .. "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<html>"
    local r = http.parse_response(raw)
    assert.equal(200, r.status)
    assert.equal("text/html", r.headers["content-type"])
    assert.is_nil(r.headers["location"]) -- only the final block's headers
    assert.equal("<html>", r.body)
  end)

  it("parses an HTTP/2 status line", function()
    local r = http.parse_response("HTTP/2 418 \r\n\r\nteapot")
    assert.equal(418, r.status)
    assert.equal("teapot", r.body)
  end)

  it("reports nil status when no HTTP/ block is present (body only)", function()
    local r = http.parse_response("just a body, no status line")
    assert.is_nil(r.status)
    assert.same({}, r.headers)
    assert.equal("just a body, no status line", r.body)
  end)
end)

describe("liv.lua.http.parse_wget_stderr", function()
  -- GNU wget -S indents response-header lines by two spaces; progress lines are not.
  it("parses the indented header block, ignoring progress lines", function()
    local stderr = "--2026-06-19--  http://example.com/\n"
      .. "Resolving example.com...\n"
      .. "Connecting to example.com...\n"
      .. "HTTP request sent, awaiting response... \n"
      .. "  HTTP/1.1 200 OK\n"
      .. "  Content-Type: text/html\n"
      .. "  Server: cloudflare\n"
      .. "Length: unspecified [text/html]\n"
      .. "Saving to: 'STDOUT'\n"
    local r = http.parse_wget_stderr(stderr)
    assert.equal(200, r.status)
    assert.equal("text/html", r.headers["content-type"])
    assert.equal("cloudflare", r.headers["server"])
    assert.is_nil(r.headers["length"]) -- a progress line, not a header
  end)

  it("returns the final block when wget follows redirects", function()
    local stderr = "  HTTP/1.1 301 Moved Permanently\n"
      .. "  Location: https://x/\n"
      .. "Location: https://x/ [following]\n"
      .. "  HTTP/1.1 200 OK\n"
      .. "  Content-Type: application/json\n"
    local r = http.parse_wget_stderr(stderr)
    assert.equal(200, r.status)
    assert.equal("application/json", r.headers["content-type"])
    assert.is_nil(r.headers["location"])
  end)

  it("returns nil status when there is no header block (e.g. busybox wget)", function()
    local r = http.parse_wget_stderr("Connecting...\nsaved\n")
    assert.is_nil(r.status)
    assert.same({}, r.headers)
  end)
end)
