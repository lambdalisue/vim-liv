-- L1 unit test for liv.lua.uri (spec 0006). Pure, editor-independent. Pins the
-- RFC 3986 generic split (parse/build), byte-wise percent coding (encode/decode),
-- and the query codec (encode_query/decode_query). These are the contracts an
-- author relies on; parse returns components RAW (no auto percent-decode), so a
-- caller composes `decode_query(parse(s).query)` deliberately.
local uri = require("liv.lua.uri")

describe("liv.lua.uri.parse", function()
  it("decomposes a full URI into every component", function()
    local p = uri.parse("https://user@host:8080/p/q?a=1&b=2#frag")
    assert.equal("https", p.scheme)
    assert.equal("user@host:8080", p.authority)
    assert.equal("user", p.userinfo)
    assert.equal("host", p.host)
    assert.equal(8080, p.port) -- integer, not "8080"
    assert.equal("/p/q", p.path)
    assert.equal("a=1&b=2", p.query)
    assert.equal("frag", p.fragment)
  end)

  it("parses an authority host without userinfo or port", function()
    local p = uri.parse("http://example.com/")
    assert.equal("http", p.scheme)
    assert.equal("example.com", p.authority)
    assert.is_nil(p.userinfo)
    assert.equal("example.com", p.host)
    assert.is_nil(p.port)
    assert.equal("/", p.path)
    assert.is_nil(p.query)
    assert.is_nil(p.fragment)
  end)

  it("treats '@' as part of the path when there is no authority (mailto:)", function()
    -- No `//` after the scheme, so there is NO authority: userinfo/host/port stay
    -- nil and the '@' belongs to the path. This is the key RFC 3986 gate.
    local p = uri.parse("mailto:foo@bar.com")
    assert.equal("mailto", p.scheme)
    assert.is_nil(p.authority)
    assert.is_nil(p.userinfo)
    assert.is_nil(p.host)
    assert.is_nil(p.port)
    assert.equal("foo@bar.com", p.path)
  end)

  it("parses the simplest mailto form", function()
    local p = uri.parse("mailto:x")
    assert.equal("mailto", p.scheme)
    assert.is_nil(p.authority)
    assert.equal("x", p.path)
  end)

  it("parses a relative reference with no scheme", function()
    local p = uri.parse("/just/a/path?q=1")
    assert.is_nil(p.scheme)
    assert.is_nil(p.authority)
    assert.equal("/just/a/path", p.path)
    assert.equal("q=1", p.query)
  end)

  it("does not mistake a path segment with a digit prefix for a scheme:port", function()
    -- A scheme must lead with a letter; "1.2.3.4:80" is not "scheme 1.2.3.4".
    local p = uri.parse("1.2.3.4:80")
    assert.is_nil(p.scheme)
    assert.equal("1.2.3.4:80", p.path)
  end)

  it("parses an empty path when authority has no trailing slash", function()
    local p = uri.parse("https://host")
    assert.equal("https", p.scheme)
    assert.equal("host", p.host)
    assert.equal("", p.path)
  end)

  it("keeps an authority with empty userinfo distinct from host", function()
    local p = uri.parse("scheme://host:1234/path")
    assert.equal("host", p.host)
    assert.equal(1234, p.port)
    assert.is_nil(p.userinfo)
  end)

  it("does not split an IPv6 literal host on its inner colons", function()
    local p = uri.parse("http://[::1]:8080/x")
    assert.equal("[::1]", p.host)
    assert.equal(8080, p.port)
    assert.equal("/x", p.path)
  end)

  it("returns the query raw without percent-decoding it", function()
    local p = uri.parse("http://host/?name=a%20b")
    assert.equal("name=a%20b", p.query) -- raw, caller decodes deliberately
  end)
end)

describe("liv.lua.uri.build", function()
  it("assembles a full URI from components", function()
    local s = uri.build({
      scheme = "https",
      userinfo = "user",
      host = "host",
      port = 8080,
      path = "/p/q",
      query = "a=1&b=2",
      fragment = "frag",
    })
    assert.equal("https://user@host:8080/p/q?a=1&b=2#frag", s)
  end)

  it("round-trips a full URI string through parse then build", function()
    local s = "https://user@host:8080/p/q?a=1&b=2#frag"
    assert.equal(s, uri.build(uri.parse(s)))
  end)

  it("round-trips mailto (no authority) at the string level", function()
    local s = "mailto:foo@bar.com"
    assert.equal(s, uri.build(uri.parse(s)))
  end)

  it("round-trips a scheme-less relative reference", function()
    local s = "/just/a/path?q=1"
    assert.equal(s, uri.build(uri.parse(s)))
  end)

  it("prefers the authority string when host components are absent", function()
    local s = uri.build({ scheme = "http", authority = "example.com", path = "/" })
    assert.equal("http://example.com/", s)
  end)

  it("composes the authority from host/port/userinfo when host is present", function()
    local s = uri.build({ scheme = "http", host = "h", port = 90, userinfo = "u" })
    assert.equal("http://u@h:90", s)
  end)

  it("reproduces a component-form table through build then parse", function()
    local p = uri.parse(uri.build({
      scheme = "https",
      userinfo = "user",
      host = "host",
      port = 8080,
      path = "/p",
      query = "a=1",
      fragment = "f",
    }))
    assert.equal("https", p.scheme)
    assert.equal("user", p.userinfo)
    assert.equal("host", p.host)
    assert.equal(8080, p.port)
    assert.equal("/p", p.path)
    assert.equal("a=1", p.query)
    assert.equal("f", p.fragment)
  end)
end)

describe("liv.lua.uri.encode", function()
  it("leaves RFC 3986 unreserved characters untouched", function()
    assert.equal("Az09-._~", uri.encode("Az09-._~"))
  end)

  it("percent-encodes reserved and other characters with uppercase hex", function()
    assert.equal("a%20b%2F%3F%26%3D", uri.encode("a b/?&="))
  end)

  it("encodes a multibyte UTF-8 string byte-wise", function()
    -- "あ" is U+3042 → UTF-8 bytes E3 81 82.
    assert.equal("%E3%81%82", uri.encode("\227\129\130"))
  end)
end)

describe("liv.lua.uri.decode", function()
  it("inverts encode for an ASCII string", function()
    assert.equal("a b/?&=", uri.decode("a%20b%2F%3F%26%3D"))
  end)

  it("inverts encode for a multibyte UTF-8 string", function()
    assert.equal("\227\129\130", uri.decode("%E3%81%82"))
  end)

  it("round-trips arbitrary text through encode then decode", function()
    local s = "Hello, 世界! a+b=c & d/e"
    assert.equal(s, uri.decode(uri.encode(s)))
  end)

  it("leaves an incomplete or invalid percent escape literal", function()
    assert.equal("100% sure", uri.decode("100% sure")) -- lone % kept
    assert.equal("%2", uri.decode("%2")) -- truncated escape kept
    assert.equal("%zz", uri.decode("%zz")) -- non-hex kept
  end)
end)

describe("liv.lua.uri.encode_query", function()
  it("encodes a flat table with deterministically sorted keys", function()
    assert.equal("a=1&b=2&c=3", uri.encode_query({ c = "3", a = "1", b = "2" }))
  end)

  it("percent-encodes keys and values (space as %20)", function()
    assert.equal("the%20key=a%20value", uri.encode_query({ ["the key"] = "a value" }))
  end)

  it("expands an array value into repeated keys in order", function()
    assert.equal("k=1&k=2&k=3", uri.encode_query({ k = { "1", "2", "3" } }))
  end)

  it("orders distinct keys by name with repeated keys grouped", function()
    assert.equal("a=1&a=2&b=3", uri.encode_query({ b = "3", a = { "1", "2" } }))
  end)
end)

describe("liv.lua.uri.decode_query", function()
  it("parses a flat query into a table", function()
    assert.same({ a = "1", b = "2" }, uri.decode_query("a=1&b=2"))
  end)

  it("percent-decodes keys and values", function()
    assert.same({ ["the key"] = "a value" }, uri.decode_query("the%20key=a%20value"))
  end)

  it("collects repeated keys into an array preserving order", function()
    assert.same({ k = { "1", "2", "3" } }, uri.decode_query("k=1&k=2&k=3"))
  end)

  it("reads a key without '=' as an empty-string value", function()
    assert.same({ a = "", b = "2" }, uri.decode_query("a&b=2"))
  end)

  it("reads an explicit empty value", function()
    assert.same({ a = "" }, uri.decode_query("a="))
  end)

  it("returns an empty table for an empty query", function()
    assert.same({}, uri.decode_query(""))
  end)
end)

-- The percent codec is the most-used, zero-dependency concern. A consumer that
-- needs only percent coding requires the leaf directly instead of the barrel,
-- which would also pull the parse/build and query machinery.
describe("liv.lua.uri.percent leaf", function()
  local percent = require("liv.lua.uri.percent")

  it("encodes through the leaf identically to the barrel", function()
    assert.equal("a%20b%2F%3F%26%3D", percent.encode("a b/?&="))
  end)

  it("decodes through the leaf identically to the barrel", function()
    assert.equal("a b/?&=", percent.decode("a%20b%2F%3F%26%3D"))
  end)
end)

describe("liv.lua.uri query round-trip", function()
  it("round-trips a flat table through encode_query then decode_query", function()
    local t = { name = "Ada", lang = "Lua 5.1", note = "a&b=c" }
    assert.same(t, uri.decode_query(uri.encode_query(t)))
  end)

  it("round-trips a table with repeated keys", function()
    local t = { tag = { "x", "y", "z" }, q = "hello world" }
    assert.same(t, uri.decode_query(uri.encode_query(t)))
  end)
end)
