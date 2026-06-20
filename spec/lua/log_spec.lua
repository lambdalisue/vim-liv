-- L1 unit test for liv.lua.log. Pure, editor-independent. Pins the level ranks,
-- the should_log gate, and the record formatting (with an INJECTED time so the
-- assertions are deterministic — no real os.time/os.date in the expectations).
local log = require("liv.lua.log")

describe("liv.lua.log.levels", function()
  it("orders the levels trace < debug < info < warn < error by rank", function()
    assert.is_true(log.rank("trace") < log.rank("debug"))
    assert.is_true(log.rank("debug") < log.rank("info"))
    assert.is_true(log.rank("info") < log.rank("warn"))
    assert.is_true(log.rank("warn") < log.rank("error"))
  end)

  it("maps a name to its rank and back", function()
    assert.equal("info", log.name(log.rank("info")))
    assert.equal("error", log.name(log.rank("error")))
  end)

  it("exposes the level table keyed by name", function()
    assert.equal(log.rank("trace"), log.levels.trace)
    assert.equal(log.rank("error"), log.levels.error)
  end)
end)

describe("liv.lua.log.should_log", function()
  it("keeps a record at or above the threshold", function()
    assert.is_true(log.should_log("info", "info"))
    assert.is_true(log.should_log("warn", "info"))
    assert.is_true(log.should_log("error", "info"))
  end)

  it("drops a record below the threshold", function()
    assert.is_false(log.should_log("debug", "info"))
    assert.is_false(log.should_log("trace", "info"))
  end)
end)

describe("liv.lua.log.format", function()
  it("formats a bare record as '[LEVEL] message'", function()
    assert.equal("[INFO] hello", log.format({ level = "info", message = "hello" }))
  end)

  it("uppercases the level tag", function()
    assert.equal("[WARN] careful", log.format({ level = "warn", message = "careful" }))
  end)

  it("prepends a UTC timestamp formatted from an injected epoch", function()
    -- 2026-01-01 12:00:00 UTC = 1767268800. The timestamp is rendered in UTC so
    -- the expectation is independent of the host timezone.
    local line = log.format({ level = "info", message = "hi", time = 1767268800 })
    assert.equal("2026-01-01 12:00:00 [INFO] hi", line)
  end)

  it("includes the source tag in parentheses when present", function()
    local line = log.format({
      level = "info",
      message = "hi",
      time = 1767268800,
      source = "myplugin",
    })
    assert.equal("2026-01-01 12:00:00 [INFO] (myplugin) hi", line)
  end)

  it("uses opts.clock to source the time when the record carries none", function()
    local line = log.format({ level = "info", message = "hi" }, {
      clock = function()
        return 1767268800
      end,
    })
    assert.equal("2026-01-01 12:00:00 [INFO] hi", line)
  end)
end)
