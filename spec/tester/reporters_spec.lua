-- L1 self-test for the liv.tester reporters (spec 0010, Phase 3).
--
-- A reporter is a pure factory `fun(opts) -> callback table`; `opts.write` is an
-- injected sink so a test captures every byte without touching stdout, and the
-- environment booleans (color/verbose/quiet) are passed in (never sniffed inside).
-- These tests feed a reporter a synthetic event stream and assert on the captured
-- output shape — no real run, no editor.
local reporters = require("liv.tester.reporters")

-- A capturing writer: returns a sink plus a reader for the accumulated text.
local function sink()
  local buf = {}
  return function(s)
    buf[#buf + 1] = s
  end, function()
    return table.concat(buf)
  end
end

-- Drive a reporter through a canned event stream describing one passed, one
-- failed, and one skipped test inside a single suite.
local function drive(reporter)
  reporter.on_run_start({})
  reporter.on_suite_enter("group")
  reporter.on_test_start("group passes")
  reporter.on_test_end({ name = "group passes", status = "passed", duration = 0.001 })
  reporter.on_test_start("group fails")
  reporter.on_test_end({
    name = "group fails",
    status = "failed",
    duration = 0.002,
    error = "boom: detail",
    file = "x_spec.lua",
    line = 42,
  })
  reporter.on_test_start("group pends")
  reporter.on_test_end({ name = "group pends", status = "skipped", duration = 0 })
  reporter.on_suite_leave("group")
  reporter.on_run_end({ passed = 1, failed = 1, skipped = 1, duration = 0.01 })
end

describe("liv.tester.reporters.tap", function()
  it("emits a 1..N plan and ok/not ok lines", function()
    local write, read = sink()
    drive(reporters.tap({ write = write }))
    local out = read()
    assert.is_not_nil(out:find("1..3", 1, true))
    assert.is_not_nil(out:find("ok 1", 1, true))
    assert.is_not_nil(out:find("not ok 2", 1, true))
  end)

  it("marks a skipped test as ok N # SKIP", function()
    local write, read = sink()
    drive(reporters.tap({ write = write }))
    assert.is_not_nil(read():find("ok 3 .* # SKIP"))
  end)

  it("writes failure detail as # diagnostic lines", function()
    local write, read = sink()
    drive(reporters.tap({ write = write }))
    -- Every diagnostic line begins with '# '.
    for line in read():gmatch("[^\n]+") do
      if line:find("boom", 1, true) then
        assert.equal("#", line:sub(1, 1))
      end
    end
  end)
end)

describe("liv.tester.reporters.jsonl", function()
  it("emits one JSON object per test result with the core fields", function()
    local write, read = sink()
    drive(reporters.jsonl({ write = write }))
    local lines = {}
    for line in read():gmatch("[^\n]+") do
      lines[#lines + 1] = line
    end
    -- One line per test result plus a final summary object.
    local result_lines = 0
    for _, line in ipairs(lines) do
      if line:find('"type":"test"', 1, true) then
        result_lines = result_lines + 1
        assert.is_not_nil(line:find('"status":', 1, true))
        assert.is_not_nil(line:find('"name":', 1, true))
        assert.is_not_nil(line:find('"duration":', 1, true))
      end
    end
    assert.equal(3, result_lines)
  end)

  it("emits a final summary object", function()
    local write, read = sink()
    drive(reporters.jsonl({ write = write }))
    assert.is_not_nil(read():find('"type":"summary"', 1, true))
  end)

  it("escapes special characters in the JSON string values", function()
    local write, read = sink()
    local r = reporters.jsonl({ write = write })
    r.on_run_start({})
    r.on_test_start('quote " and \\ backslash')
    r.on_test_end({ name = 'quote " and \\ backslash', status = "passed", duration = 0 })
    r.on_run_end({ passed = 1, failed = 0, skipped = 0, duration = 0 })
    -- The raw quote and backslash must be escaped in the output.
    assert.is_not_nil(read():find('\\"', 1, true))
    assert.is_not_nil(read():find("\\\\", 1, true))
  end)
end)

describe("liv.tester.reporters.spec", function()
  it("marks pass/fail/skip with distinct glyphs and shows per-test ms", function()
    local write, read = sink()
    drive(reporters.spec({ write = write, color = false }))
    local out = read()
    assert.is_not_nil(out:find("✓", 1, true))
    assert.is_not_nil(out:find("✗", 1, true))
    assert.is_not_nil(out:find("⊘", 1, true))
    assert.is_not_nil(out:find("ms", 1, true))
  end)

  it("prints the suite name once as a heading", function()
    local write, read = sink()
    drive(reporters.spec({ write = write, color = false }))
    assert.is_not_nil(read():find("group", 1, true))
  end)

  it("does not emit ANSI escapes when color is off", function()
    local write, read = sink()
    drive(reporters.spec({ write = write, color = false }))
    assert.is_nil(read():find("\27[", 1, true))
  end)

  it("emits ANSI escapes when color is on", function()
    local write, read = sink()
    drive(reporters.spec({ write = write, color = true }))
    assert.is_not_nil(read():find("\27[", 1, true))
  end)

  it("highlights a slow test past the threshold", function()
    local write, read = sink()
    local r = reporters.spec({ write = write, color = false, slow_threshold = 0.05 })
    r.on_run_start({})
    r.on_suite_enter("g")
    r.on_test_start("g slow")
    r.on_test_end({ name = "g slow", status = "passed", duration = 0.5 })
    r.on_suite_leave("g")
    r.on_run_end({ passed = 1, failed = 0, skipped = 0, duration = 0.5 })
    assert.is_not_nil(read():find("SLOW", 1, true))
  end)
end)

describe("liv.tester.reporters.junit", function()
  it("emits a testsuite element with the run totals", function()
    local write, read = sink()
    drive(reporters.junit({ write = write }))
    local out = read()
    assert.is_not_nil(out:find("<testsuite", 1, true))
    assert.is_not_nil(out:find('tests="3"', 1, true))
    assert.is_not_nil(out:find('failures="1"', 1, true))
    assert.is_not_nil(out:find('skipped="1"', 1, true))
  end)

  it("emits a testcase per test, with failure and skipped children", function()
    local write, read = sink()
    drive(reporters.junit({ write = write }))
    local out = read()
    assert.is_not_nil(out:find("<testcase", 1, true))
    assert.is_not_nil(out:find("<failure", 1, true))
    assert.is_not_nil(out:find("<skipped", 1, true))
  end)

  it("escapes XML special characters in names", function()
    local write, read = sink()
    local r = reporters.junit({ write = write })
    r.on_run_start({})
    r.on_test_start("a < b & c")
    r.on_test_end({ name = "a < b & c", status = "passed", duration = 0 })
    r.on_run_end({ passed = 1, failed = 0, skipped = 0, duration = 0 })
    local out = read()
    assert.is_not_nil(out:find("&lt;", 1, true))
    assert.is_not_nil(out:find("&amp;", 1, true))
  end)
end)

describe("liv.tester.reporters.get", function()
  it("resolves a reporter by name", function()
    assert.is_function(reporters.get("tap"))
    assert.is_function(reporters.get("spec"))
    assert.is_function(reporters.get("jsonl"))
    assert.is_function(reporters.get("junit"))
  end)

  it("returns nil for an unknown reporter name", function()
    assert.is_nil(reporters.get("nope"))
  end)
end)
