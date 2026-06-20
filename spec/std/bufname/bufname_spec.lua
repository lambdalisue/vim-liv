-- L1 unit test for the pure bufname codec (spec 0006). Deterministic on any host.
local bufname = require("liv.std.bufname.bufname")

describe("bufname.format", function()
  it("formats scheme and expr into the wire form", function()
    assert.equal("aiboconsole://bash", bufname.format({ scheme = "aiboconsole", expr = "bash" }))
  end)

  it("percent-encodes Windows-unsafe characters in expr", function()
    assert.equal(
      "file://a%3C%3E%7C%3F%2A%22b",
      bufname.format({
        scheme = "file",
        expr = 'a<>|?*"b',
      })
    )
  end)

  it("appends sorted params after a semicolon", function()
    assert.equal(
      "x://e;a=1&b=2",
      bufname.format({
        scheme = "x",
        expr = "e",
        params = { b = "2", a = "1" },
      })
    )
  end)

  it("repeats a key for multi-value params, preserving array order", function()
    assert.equal(
      "x://e;k=1&k=2&k=3",
      bufname.format({
        scheme = "x",
        expr = "e",
        params = { k = { "1", "2", "3" } },
      })
    )
  end)

  it("appends a fragment after a hash", function()
    assert.equal(
      "aiboprompt://1#lua",
      bufname.format({
        scheme = "aiboprompt",
        expr = "1",
        fragment = "lua",
      })
    )
  end)

  it("raises on a non-alphabetic scheme", function()
    assert.has_error(function()
      bufname.format({ scheme = "abc123", expr = "e" })
    end)
    assert.has_error(function()
      bufname.format({ scheme = "a+b", expr = "e" })
    end)
  end)
end)

describe("bufname.parse", function()
  it("parses scheme and expr", function()
    local r = bufname.parse("aiboconsole://bash")
    assert.equal("aiboconsole", r.scheme)
    assert.equal("bash", r.expr)
    assert.is_nil(r.params)
    assert.is_nil(r.fragment)
  end)

  it("decodes Windows-unsafe characters in expr", function()
    local r = bufname.parse("file://a%3C%3E%7C%3F%2A%22b")
    assert.equal('a<>|?*"b', r.expr)
  end)

  it("parses a single param as a string", function()
    local r = bufname.parse("x://e;a=1")
    assert.equal("1", r.params.a)
  end)

  it("parses a repeated key as a list in order", function()
    local r = bufname.parse("x://e;k=1&k=2&k=3")
    assert.same({ "1", "2", "3" }, r.params.k)
  end)

  it("parses a fragment", function()
    local r = bufname.parse("aiboprompt://1#lua")
    assert.equal("lua", r.fragment)
  end)

  it("raises when the '://' separator is missing", function()
    assert.has_error(function()
      bufname.parse("noseparator")
    end)
  end)

  it("raises on a non-alphabetic scheme", function()
    assert.has_error(function()
      bufname.parse("ab12://e")
    end)
  end)
end)

describe("bufname round-trip (parse(format(x)) == x)", function()
  local function round_trip(obj)
    assert.same(obj, bufname.parse(bufname.format(obj)))
  end

  it("round-trips a bare scheme/expr", function()
    round_trip({ scheme = "aiboconsole", expr = "bash" })
  end)

  it("round-trips Windows-unsafe characters in expr", function()
    round_trip({ scheme = "file", expr = 'a<>|?*"b' })
  end)

  it("round-trips a literal percent-escape sequence in expr", function()
    -- "%3C" is literal text, not an encoding; it must survive as-is.
    round_trip({ scheme = "x", expr = "%3C raw %25 text" })
  end)

  it("round-trips structural delimiters in expr", function()
    round_trip({ scheme = "x", expr = "has;semi#hash&amp=eq" })
  end)

  it("round-trips single and multi-value params", function()
    round_trip({ scheme = "x", expr = "e", params = { a = "1", b = { "2", "3" } } })
  end)

  it("round-trips param values containing delimiters", function()
    round_trip({ scheme = "x", expr = "e", params = { q = "a=b&c;d#e%f" } })
  end)

  it("round-trips a fragment", function()
    round_trip({ scheme = "aiboprompt", expr = "1", fragment = "lua" })
  end)

  it("round-trips expr + params + fragment together", function()
    round_trip({
      scheme = "aiboconsole",
      expr = "claude/--model/opus",
      params = { tab = "2", buf = { "10", "11" } },
      fragment = "aibo-tool-claude",
    })
  end)
end)
