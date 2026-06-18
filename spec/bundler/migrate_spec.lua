-- L1 unit test for liv.bundler.migrate. Pure, no editor.
local migrate = require("liv.bundler.migrate")

-- A realistic MIGRATIONS.md: a markdown header, prose, a fenced format example
-- (must be ignored), then two real entries.
local DOC = [[
# Migrations

Breaking-change notices. Format:

```
<version>
    Modules: <list>
    <desc>
```

2.0.0
    Modules: std.buffer, std.window
    lines() ranges are now 1-based inclusive (was 0-based).
1.4.0
    Modules: *
    Lua 5.1 dialect mandated; bitwise ops via the shim.
]]

local function set(...)
  local s = {}
  for _, v in ipairs({ ... }) do
    s[v] = true
  end
  return s
end

describe("liv.bundler.migrate.compare", function()
  it("orders dotted versions numerically", function()
    assert.equal(-1, migrate.compare("1.4.0", "2.0.0"))
    assert.equal(1, migrate.compare("2.0.1", "2.0.0"))
    assert.equal(0, migrate.compare("2.0", "2.0.0"))
  end)
end)

describe("liv.bundler.migrate.parse", function()
  it("parses real entries and ignores the header, prose, and fenced example", function()
    local entries = migrate.parse(DOC)
    assert.equal(2, #entries)
    assert.equal("2.0.0", entries[1].version)
    assert.same({ "std.buffer", "std.window" }, entries[1].modules)
    assert.equal("lines() ranges are now 1-based inclusive (was 0-based).", entries[1].description)
    assert.equal("*", entries[2].modules)
  end)
end)

describe("liv.bundler.migrate.relevant", function()
  local entries = migrate.parse(DOC)

  it("returns only entries in (from, to] affecting a bundled module, oldest first", function()
    -- bundling liv.std.buffer, updating 1.0.0 -> 2.0.0: both the * entry (1.4.0)
    -- and the std.buffer entry (2.0.0) apply
    local r = migrate.relevant(entries, "1.0.0", "2.0.0", set("liv.std.buffer", "liv.core"))
    assert.equal(2, #r)
    assert.equal("1.4.0", r[1].version) -- oldest first
    assert.equal("2.0.0", r[2].version)
  end)

  it("excludes entries that affect no bundled module", function()
    -- bundling only liv.core: 2.0.0 targets std.buffer/std.window (not core), but
    -- 1.4.0 is Modules: * so it still applies
    local r = migrate.relevant(entries, "1.0.0", "2.0.0", set("liv.core"))
    assert.equal(1, #r)
    assert.equal("1.4.0", r[1].version)
  end)

  it("excludes entries outside the version range", function()
    -- already on 1.4.0; updating to 1.9.0 crosses nothing (2.0.0 is above to)
    local r = migrate.relevant(entries, "1.4.0", "1.9.0", set("liv.std.buffer"))
    assert.equal(0, #r)
  end)
end)
