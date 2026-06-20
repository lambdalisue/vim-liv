-- L1 self-test for the liv.tester selector mini-language (spec 0010).
-- Exercises parse/compile/match directly (no nested run), so it does not
-- perturb the surrounding suite's pass/fail counts.
local select = require("liv.tester._select")

describe("liv.tester selector", function()
  it("a bare word matches the full title (name:)", function()
    local match = select.compile({ "login" })
    assert.is_true(match("user login flow", {}))
    assert.is_false(match("logout flow", {}))
  end)

  it("name: matches the full title with a Lua pattern", function()
    local match = select.compile({ "name:log%w+" })
    assert.is_true(match("does logging", {}))
    assert.is_false(match("does parsing", {}))
  end)

  it("is case-insensitive", function()
    local match = select.compile({ "name:LOGIN" })
    assert.is_true(match("User Login", {}))
  end)

  it("tag: matches any of the test's tags", function()
    local match = select.compile({ "tag:slow" })
    assert.is_true(match("anything", { "slow", "db" }))
    assert.is_false(match("anything", { "fast" }))
  end)

  it("! negates a term", function()
    local match = select.compile({ "!tag:slow" })
    assert.is_true(match("anything", { "fast" }))
    assert.is_false(match("anything", { "slow" }))
  end)

  it("comma within one selector is AND", function()
    local match = select.compile({ "name:login,tag:smoke" })
    assert.is_true(match("login page", { "smoke" }))
    assert.is_false(match("login page", { "other" }))
    assert.is_false(match("home page", { "smoke" }))
  end)

  it("multiple selectors are OR", function()
    local match = select.compile({ "tag:smoke", "name:login" })
    assert.is_true(match("login page", {}))
    assert.is_true(match("home page", { "smoke" }))
    assert.is_false(match("home page", { "other" }))
  end)

  it("an empty selector list matches everything", function()
    local match = select.compile({})
    assert.is_true(match("anything", {}))
  end)

  it(
    "ignores non-string entries (a bare --select parses to boolean true), never crashing",
    function()
      -- `--select` with no `=value` becomes boolean true under the no-lookahead
      -- argument parser; compile must degrade to match-all, not index the boolean.
      local match = select.compile({ true })
      assert.is_true(match("anything", {}))
      -- a real selector mixed with a bare flag still filters by the real one.
      local mixed = select.compile({ true, "tag:slow" })
      assert.is_true(mixed("x", { "slow" }))
      assert.is_false(mixed("x", { "fast" }))
    end
  )
end)
