-- L1 self-test for the async test helper (spec 0010).
-- The helper drives a liv.lua.async async function to completion SYNCHRONOUSLY
-- over the pure runner with a drainable fake schedule, so authors stop
-- hand-rolling the queue+drain pattern in every async test.
local tester = require("liv.tester")
local async = require("liv.lua.async")

describe("liv.tester async helper", function()
  it("drives an async fn to completion and returns its value", function()
    local result = tester.async(function()
      local v = async.await(function(resume)
        resume(true, 7)
      end)
      return v * 6
    end)
    assert.equal(42, result)
  end)

  it("runs multi-hop async code, resuming through the shared schedule", function()
    local result = tester.async(function()
      local total = 0
      for _ = 1, 3 do
        total = total + async.await(function(resume)
          resume(true, 1)
        end)
      end
      return total
    end)
    assert.equal(3, result)
  end)

  it("re-raises an error thrown inside the async fn", function()
    local err = tester.assert.has_error(function()
      tester.async(function()
        error("inside-async")
      end)
    end)
    assert.is_not_nil(tostring(err):find("inside-async", 1, true))
  end)

  it("re-raises an awaited failure", function()
    local err = tester.assert.has_error(function()
      tester.async(function()
        async.await(function(resume)
          resume(false, "awaited-fail")
        end)
      end)
    end)
    assert.is_not_nil(tostring(err):find("awaited-fail", 1, true))
  end)

  it("errors when the async fn never completes (queue drains, never settles)", function()
    local err = tester.assert.has_error(function()
      tester.async(function()
        -- Park forever: await a task that never resumes.
        async.await(function() end)
      end)
    end)
    assert.is_not_nil(tostring(err):find("did not complete", 1, true))
  end)

  it("supports it.async as an it whose body is driven to completion", function()
    -- Build a hermetic registry so this self-test never perturbs the live run.
    local t = tester.new()
    local seen
    t.describe("g", function()
      t.it.async("awaits", function()
        seen = async.await(function(resume)
          resume(true, "done")
        end)
      end)
    end)
    local passed, failed = t.run()
    assert.equal(1, passed)
    assert.equal(0, failed)
    assert.equal("done", seen)
  end)

  it("it.async surfaces an async failure as a failed test", function()
    local t = tester.new()
    t.describe("g", function()
      t.it.async("boom", function()
        error("async-test-boom")
      end)
    end)
    local passed, failed, _skipped, failures = t.run()
    assert.equal(0, passed)
    assert.equal(1, failed)
    assert.is_not_nil(tostring(failures[1].err):find("async-test-boom", 1, true))
  end)
end)
