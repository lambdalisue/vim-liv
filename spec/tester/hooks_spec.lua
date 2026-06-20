-- L1 self-test for describe-scoped hooks (before_all/after_all) and per-test
-- finally (spec 0010). Each case builds a HERMETIC registry via tester.new() so
-- it never perturbs the surrounding live run. Hooks are asserted by the ORDER
-- and COUNT of entries pushed into a shared log.
local tester = require("liv.tester")

describe("liv.tester before_all / after_all", function()
  it("runs before_all once before the first test and after_all once after the last", function()
    local t = tester.new()
    local log = {}
    t.describe("g", function()
      t.before_all(function()
        log[#log + 1] = "before_all"
      end)
      t.after_all(function()
        log[#log + 1] = "after_all"
      end)
      t.it("a", function()
        log[#log + 1] = "a"
      end)
      t.it("b", function()
        log[#log + 1] = "b"
      end)
    end)
    t.run()
    assert.same({ "before_all", "a", "b", "after_all" }, log)
  end)

  it("nests outermost-first for before_all and innermost-first for after_all", function()
    local t = tester.new()
    local log = {}
    t.describe("outer", function()
      t.before_all(function()
        log[#log + 1] = "outer.before_all"
      end)
      t.after_all(function()
        log[#log + 1] = "outer.after_all"
      end)
      t.describe("inner", function()
        t.before_all(function()
          log[#log + 1] = "inner.before_all"
        end)
        t.after_all(function()
          log[#log + 1] = "inner.after_all"
        end)
        t.it("x", function()
          log[#log + 1] = "x"
        end)
      end)
    end)
    t.run()
    assert.same({
      "outer.before_all",
      "inner.before_all",
      "x",
      "inner.after_all",
      "outer.after_all",
    }, log)
  end)

  it("orders before_all before before_each and after_all after after_each", function()
    local t = tester.new()
    local log = {}
    t.describe("g", function()
      t.before_all(function()
        log[#log + 1] = "before_all"
      end)
      t.before_each(function()
        log[#log + 1] = "before_each"
      end)
      t.after_each(function()
        log[#log + 1] = "after_each"
      end)
      t.after_all(function()
        log[#log + 1] = "after_all"
      end)
      t.it("a", function()
        log[#log + 1] = "a"
      end)
    end)
    t.run()
    assert.same({ "before_all", "before_each", "a", "after_each", "after_all" }, log)
  end)

  it("does NOT run a describe's before_all when none of its tests run (filtered out)", function()
    local t = tester.new()
    local ran = false
    t.describe("untouched", function()
      t.before_all(function()
        ran = true
      end)
      t.it("never", function() end)
    end)
    local select = require("liv.tester._select")
    -- A selector that matches nothing in this subtree makes every test a
    -- non-candidate; before_all must stay lazy and never fire.
    t.run(nil, { filter = select.compile({ "name:nomatch" }) })
    assert.is_false(ran)
  end)

  it("does NOT run an unfocused sibling's before_all when focus is elsewhere", function()
    local t = tester.new()
    local ran = false
    t.describe("focused", function()
      t.it.only("here", function() end)
    end)
    t.describe("sibling", function()
      t.before_all(function()
        ran = true
      end)
      t.it("there", function() end)
    end)
    t.run()
    assert.is_false(ran)
  end)

  it("runs before_all/after_all only ONCE across many tests", function()
    local t = tester.new()
    local befores, afters = 0, 0
    t.describe("g", function()
      t.before_all(function()
        befores = befores + 1
      end)
      t.after_all(function()
        afters = afters + 1
      end)
      t.it("a", function() end)
      t.it("b", function() end)
      t.it("c", function() end)
    end)
    t.run()
    assert.equal(1, befores)
    assert.equal(1, afters)
  end)

  it("still runs after_all once even when a test fails", function()
    local t = tester.new()
    local after = 0
    t.describe("g", function()
      t.after_all(function()
        after = after + 1
      end)
      t.it("boom", function()
        error("nope")
      end)
    end)
    local _passed, failed = t.run()
    assert.equal(1, failed)
    assert.equal(1, after)
  end)
end)

describe("liv.tester finally", function()
  it("runs a finally after the body even when the body succeeds", function()
    local t = tester.new()
    local log = {}
    t.describe("g", function()
      t.it("a", function()
        t.finally(function()
          log[#log + 1] = "cleanup"
        end)
        log[#log + 1] = "body"
      end)
    end)
    t.run()
    assert.same({ "body", "cleanup" }, log)
  end)

  it("runs finally even when the body errors, and the test still fails", function()
    local t = tester.new()
    local cleaned = false
    t.describe("g", function()
      t.it("a", function()
        t.finally(function()
          cleaned = true
        end)
        error("boom")
      end)
    end)
    local _passed, failed = t.run()
    assert.equal(1, failed)
    assert.is_true(cleaned)
  end)

  it("runs multiple finallys in reverse registration order", function()
    local t = tester.new()
    local log = {}
    t.describe("g", function()
      t.it("a", function()
        t.finally(function()
          log[#log + 1] = "first"
        end)
        t.finally(function()
          log[#log + 1] = "second"
        end)
      end)
    end)
    t.run()
    assert.same({ "second", "first" }, log)
  end)

  it("a finally registered before pending still runs", function()
    local t = tester.new()
    local cleaned = false
    t.describe("g", function()
      t.it("wip", function()
        t.finally(function()
          cleaned = true
        end)
        t.pending("later")
      end)
    end)
    local _passed, _failed, skipped = t.run()
    assert.equal(1, skipped)
    assert.is_true(cleaned)
  end)

  it("a finally that errors fails an otherwise-passing test", function()
    local t = tester.new()
    t.describe("g", function()
      t.it("a", function()
        t.finally(function()
          error("cleanup-failed")
        end)
      end)
    end)
    local _passed, failed, _skipped, failures = t.run()
    assert.equal(1, failed)
    assert.is_not_nil(tostring(failures[1].err):find("cleanup-failed", 1, true))
  end)

  it("a finally that errors turns a pending test into a failure", function()
    local t = tester.new()
    t.describe("g", function()
      t.it("wip", function()
        t.finally(function()
          error("cleanup-after-pending")
        end)
        t.pending("later")
      end)
    end)
    local _passed, failed, skipped, failures = t.run()
    assert.equal(1, failed)
    assert.equal(0, skipped)
    assert.is_not_nil(tostring(failures[1].err):find("cleanup-after-pending", 1, true))
  end)

  it("runs finally before after_each", function()
    local t = tester.new()
    local log = {}
    t.describe("g", function()
      t.after_each(function()
        log[#log + 1] = "after_each"
      end)
      t.it("a", function()
        t.finally(function()
          log[#log + 1] = "finally"
        end)
      end)
    end)
    t.run()
    assert.same({ "finally", "after_each" }, log)
  end)

  it("does not leak finallys from one test into the next", function()
    local t = tester.new()
    local count = 0
    t.describe("g", function()
      t.it("first", function()
        t.finally(function()
          count = count + 1
        end)
      end)
      t.it("second", function() end)
    end)
    t.run()
    assert.equal(1, count)
  end)
end)
