-- L1 self-test for the liv.tester reporter EVENT interface (spec 0010, Phase 3).
--
-- A reporter is a table of optional callbacks; run() drives them as it walks the
-- tree. These tests install a FAKE reporter that records every event into a flat
-- log, so the event seam is asserted without any real reporter or editor. Each
-- case builds a HERMETIC registry via tester.new() so it never perturbs the live
-- run.
local tester = require("liv.tester")

-- A fake reporter that appends a tag per event to `log`, capturing the payloads.
local function recorder()
  local log = {}
  local reports = {}
  local stats
  local ctx
  return {
    log = log,
    reports = reports,
    ctx_of = function()
      return ctx
    end,
    stats_of = function()
      return stats
    end,
    reporter = {
      on_run_start = function(c)
        log[#log + 1] = "run_start"
        ctx = c
      end,
      on_layer_enter = function(name)
        log[#log + 1] = "layer_enter:" .. name
      end,
      on_suite_enter = function(name)
        log[#log + 1] = "suite_enter:" .. name
      end,
      on_suite_leave = function(name)
        log[#log + 1] = "suite_leave:" .. name
      end,
      on_test_start = function(name)
        log[#log + 1] = "test_start:" .. name
      end,
      on_test_end = function(report)
        log[#log + 1] = "test_end:" .. report.status
        reports[#reports + 1] = report
      end,
      on_run_end = function(s)
        log[#log + 1] = "run_end"
        stats = s
      end,
    },
  }
end

describe("liv.tester reporter event interface", function()
  it("emits run_start, suite enter/leave, test start/end, run_end in order", function()
    local t = tester.new()
    t.describe("group", function()
      t.it("a", function() end)
    end)
    local rec = recorder()
    t.run(rec.reporter)
    assert.same({
      "run_start",
      "suite_enter:group",
      "test_start:group a",
      "test_end:passed",
      "suite_leave:group",
      "run_end",
    }, rec.log)
  end)

  it("does not emit on_layer_enter (layers are sectioned by the CLI, not run)", function()
    local t = tester.new()
    t.describe("group", function()
      t.it("a", function() end)
    end)
    local rec = recorder()
    t.run(rec.reporter)
    for _, entry in ipairs(rec.log) do
      assert.is_nil(entry:find("layer_enter", 1, true))
    end
  end)

  it("emits a test_end for skipped and failed tests too", function()
    local t = tester.new()
    t.describe("g", function()
      t.it("ok", function() end)
      t.it("bad", function()
        error("boom")
      end)
      t.it.skip("skip", function() end)
    end)
    local rec = recorder()
    t.run(rec.reporter)
    local statuses = {}
    for _, r in ipairs(rec.reports) do
      statuses[#statuses + 1] = r.status
    end
    assert.same({ "passed", "failed", "skipped" }, statuses)
  end)

  it("includes name, status, and a numeric duration on each report", function()
    local t = tester.new()
    t.describe("g", function()
      t.it("a", function() end)
    end)
    local rec = recorder()
    t.run(rec.reporter)
    local report = rec.reports[1]
    assert.equal("g a", report.name)
    assert.equal("passed", report.status)
    assert.is_number(report.duration)
    assert.is_true(report.duration >= 0)
  end)

  it("carries the error on a failed report", function()
    local t = tester.new()
    t.describe("g", function()
      t.it("bad", function()
        error("kaboom")
      end)
    end)
    local rec = recorder()
    t.run(rec.reporter)
    local report = rec.reports[1]
    assert.equal("failed", report.status)
    assert.is_not_nil(tostring(report.error):find("kaboom", 1, true))
  end)

  it("passes aggregate stats to on_run_end", function()
    local t = tester.new()
    t.describe("g", function()
      t.it("a", function() end)
      t.it("b", function()
        error("x")
      end)
      t.it.skip("c", function() end)
    end)
    local rec = recorder()
    t.run(rec.reporter)
    local stats = rec.stats_of()
    assert.equal(1, stats.passed)
    assert.equal(1, stats.failed)
    assert.equal(1, stats.skipped)
    assert.is_number(stats.duration)
  end)

  it("still returns passed, failed, skipped, failures (back-compat)", function()
    local t = tester.new()
    t.describe("g", function()
      t.it("a", function() end)
      t.it("b", function()
        error("x")
      end)
    end)
    local passed, failed, skipped, failures = t.run(recorder().reporter)
    assert.equal(1, passed)
    assert.equal(1, failed)
    assert.equal(0, skipped)
    assert.equal(1, #failures)
  end)

  it("accepts a legacy on_progress function as the first argument", function()
    local t = tester.new()
    t.describe("g", function()
      t.it("a", function() end)
      t.it("b", function()
        error("x")
      end)
      t.it.skip("c", function() end)
    end)
    local seen = {}
    t.run(function(status)
      seen[#seen + 1] = status
    end)
    assert.same({ "passed", "failed", "skipped" }, seen)
  end)

  it("treats a reporter and opts as separate arguments", function()
    local t = tester.new()
    t.describe("g", function()
      t.it("alpha", function() end)
      t.it("beta", function() end)
    end)
    local rec = recorder()
    local select = require("liv.tester._select")
    t.run(rec.reporter, { filter = select.compile({ "name:alpha" }) })
    local names = {}
    for _, r in ipairs(rec.reports) do
      names[#names + 1] = r.name
    end
    assert.same({ "g alpha" }, names)
  end)
end)
