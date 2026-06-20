-- L1 unit test for liv.lua.argument (spec 0009). Pure, editor-independent. Pins
-- the command-argument parser that liv.std.command handlers rely on instead of
-- re-implementing flag parsing per plugin: `split` (quote-aware tokenizer) and
-- `parse` (Vim-style `++opt` long-options + `-f`/`--flag` flags + positional
-- residue), plus the optional `format` inverse used to rebuild a command line.
local argument = require("liv.lua.argument")

describe("liv.lua.argument.split", function()
  it("splits on unquoted runs of whitespace", function()
    assert.same({ "a", "b", "c" }, argument.split("a  b\tc"))
  end)

  it("keeps a single-quoted run as one token (quotes removed)", function()
    assert.same({ "a b" }, argument.split("'a b'"))
  end)

  it("keeps a double-quoted run as one token (quotes removed)", function()
    assert.same({ "c d" }, argument.split('"c d"'))
  end)

  it("treats a backslash as escaping the next character", function()
    assert.same({ "a b" }, argument.split("a\\ b"))
  end)

  it("emits an empty-string token for empty quotes", function()
    assert.same({ "" }, argument.split("''"))
    assert.same({ "x", "", "y" }, argument.split("x '' y"))
  end)

  it("returns an empty array for empty or whitespace-only input", function()
    assert.same({}, argument.split(""))
    assert.same({}, argument.split("   \t  "))
  end)

  it("is lenient with an unterminated quote (emits what it has)", function()
    assert.same({ "a b" }, argument.split("'a b"))
  end)

  it("does not treat quotes inside a bare word as delimiters", function()
    assert.same({ "ab cd" }, argument.split("a'b c'd"))
  end)
end)

describe("liv.lua.argument.parse", function()
  it("parses the canonical mix of opts, flags, and positionals", function()
    local opts, flags, rest = argument.parse("++enc=utf8 -f --foo=bar --foo=baz hello world")
    assert.same({ enc = "utf8" }, opts)
    assert.same({ f = true, foo = { "bar", "baz" } }, flags)
    assert.same({ "hello", "world" }, rest)
  end)

  it("accepts an array of already-split tokens (no re-splitting)", function()
    local opts, flags, rest = argument.parse({ "++enc=utf8", "--name=a b", "pos" })
    assert.same({ enc = "utf8" }, opts)
    assert.same({ name = "a b" }, flags) -- token kept verbatim, not re-split
    assert.same({ "pos" }, rest)
  end)

  it("reads a valueless `++name` opt as boolean true", function()
    local opts = argument.parse("++binary ++enc=latin1")
    assert.same({ binary = true, enc = "latin1" }, opts)
  end)

  it("reads a valueless `--name` long flag as boolean true", function()
    local _, flags = argument.parse("--verbose")
    assert.same({ verbose = true }, flags)
  end)

  it("never consumes the following token as a value for a `=`-less flag", function()
    -- `--foo bar` is `flags.foo = true` plus positional `bar`; values arrive
    -- ONLY via `=`. No lookahead, so parsing stays deterministic.
    local _, flags, rest = argument.parse("--foo bar")
    assert.same({ foo = true }, flags)
    assert.same({ "bar" }, rest)
  end)

  it("collects a repeated long flag into an array preserving order", function()
    local _, flags = argument.parse("--inc=a --inc=b --inc=c")
    assert.same({ inc = { "a", "b", "c" } }, flags)
  end)

  it("collects a repeated opt into an array preserving order", function()
    local opts = argument.parse("++set=a ++set=b")
    assert.same({ set = { "a", "b" } }, opts)
  end)

  it("promotes a boolean-then-value repeat into an array", function()
    -- `--foo --foo=bar`: first true, then "bar" -> { true, "bar" }.
    local _, flags = argument.parse("--foo --foo=bar")
    assert.same({ foo = { true, "bar" } }, flags)
  end)

  it("treats a literal `--` as the end of option parsing", function()
    -- Everything after `--` is positional, even if it looks like a flag/opt;
    -- opts/flags BEFORE the `--` are parsed normally.
    local opts, flags, rest = argument.parse("++enc=utf8 --keep -- --not-a-flag ++not-an-opt pos")
    assert.same({ enc = "utf8" }, opts)
    assert.same({ keep = true }, flags)
    assert.same({ "--not-a-flag", "++not-an-opt", "pos" }, rest)
  end)

  it("keeps unknown opts and flags (no schema, no validation)", function()
    local opts, flags = argument.parse("++anything=1 --whatever=2 -z")
    assert.same({ anything = "1" }, opts)
    assert.same({ whatever = "2", z = true }, flags)
  end)

  it("returns three empty tables for empty input", function()
    local opts, flags, rest = argument.parse("")
    assert.same({}, opts)
    assert.same({}, flags)
    assert.same({}, rest)
  end)

  it("returns three empty tables for an empty token array", function()
    local opts, flags, rest = argument.parse({})
    assert.same({}, opts)
    assert.same({}, flags)
    assert.same({}, rest)
  end)

  it("handles positional-only input", function()
    local opts, flags, rest = argument.parse("one two three")
    assert.same({}, opts)
    assert.same({}, flags)
    assert.same({ "one", "two", "three" }, rest)
  end)

  it("handles flag-only input", function()
    local _, flags, rest = argument.parse("-a -b --c")
    assert.same({ a = true, b = true, c = true }, flags)
    assert.same({}, rest)
  end)

  it("treats a bare `-` as a positional, not a flag", function()
    local _, flags, rest = argument.parse("-")
    assert.same({}, flags)
    assert.same({ "-" }, rest)
  end)

  it("treats an empty `=` value as an empty string", function()
    local _, flags = argument.parse("--name=")
    assert.same({ name = "" }, flags)
  end)

  it("supports a value that contains `=` (only the first splits)", function()
    local _, flags = argument.parse("--expr=a=b=c")
    assert.same({ expr = "a=b=c" }, flags)
  end)

  it("treats a multi-character short cluster as a single flag key", function()
    -- Short-flag clustering is out of scope: `-abc` is one flag named `abc`,
    -- NOT three flags `a`/`b`/`c`. Documented, deterministic, never a crash.
    local _, flags = argument.parse("-abc")
    assert.same({ abc = true }, flags)
  end)
end)

describe("liv.lua.argument.format", function()
  it("renders opts, flags, and rest back into a command line", function()
    local s = argument.format({ enc = "utf8" }, { f = true, foo = "bar" }, { "pos" })
    -- Deterministic: opts then flags (sorted by key: `f` < `foo`), then
    -- positionals.
    assert.equal("++enc=utf8 -f --foo=bar pos", s)
  end)

  it("round-trips parse semantically (parse . format == identity)", function()
    local opts0 = { enc = "utf8" }
    local flags0 = { f = true, foo = { "bar", "baz" }, verbose = true }
    local rest0 = { "hello", "a positional with spaces" }
    local opts1, flags1, rest1 = argument.parse(argument.format(opts0, flags0, rest0))
    assert.same(opts0, opts1)
    assert.same(flags0, flags1)
    assert.same(rest0, rest1)
  end)

  it("quotes a positional that contains whitespace so it re-splits", function()
    local s = argument.format({}, {}, { "a b" })
    assert.same({ "a b" }, argument.split(s))
  end)

  it("emits a `--` so an option-like positional survives the round-trip", function()
    -- "--foo"/"-x"/"++opt"/"--" as positionals must come back as `rest`, not
    -- re-parse as flags/opts; format guards them with a `--` terminator.
    local rest0 = { "--foo", "-x", "++opt", "--" }
    local opts, flags, rest = argument.parse(argument.format({}, {}, rest0))
    assert.same({}, opts)
    assert.same({}, flags)
    assert.same(rest0, rest)
  end)

  it("round-trips a positional containing a backslash", function()
    local rest0 = { "a\\b" }
    local _, _, rest = argument.parse(argument.format({}, {}, rest0))
    assert.same(rest0, rest)
  end)
end)
