-- L3 integration test for liv.std.task (spec 0007): the editor-bound async
-- runner driven across a REAL editor loop on both Vim and Neovim. The tests are
-- chosen to discriminate a working engine from a broken one — a synchronous or
-- never-resuming implementation fails them.
local task = require("liv.std.task")

describe("liv.std.task (L3)", function()
  it("schedule runs a function on the loop", function()
    local hit = false
    task.schedule(function()
      hit = true
    end)
    -- pump the loop by running a short task to completion
    task.block(
      task.run(function()
        task.sleep(20)
        return true
      end),
      1000
    )
    assert.is_true(hit)
  end)

  it("schedule preserves FIFO order (Vim fires same-delay timers LIFO natively)", function()
    local order = {}
    task.schedule(function()
      order[#order + 1] = 1
    end)
    task.schedule(function()
      order[#order + 1] = 2
    end)
    task.schedule(function()
      order[#order + 1] = 3
    end)
    task.block(
      task.run(function()
        task.sleep(20)
        return true
      end),
      1000
    )
    assert.same({ 1, 2, 3 }, order)
  end)

  it("run drives an async function to completion", function()
    local handle = task.run(function()
      local x = task.await(function(resume)
        resume(true, 21)
      end)
      return x * 2
    end)
    local ok, result = task.block(handle, 1000)
    assert.is_true(handle.done)
    assert.is_true(ok)
    assert.equal(42, result)
  end)

  it("sleep suspends then resumes across a real timer (ordering)", function()
    local order = {}
    local handle = task.run(function()
      order[#order + 1] = "before"
      task.sleep(20)
      order[#order + 1] = "after"
      return "ok"
    end)
    task.block(handle, 1000)
    assert.is_true(handle.done)
    assert.same({ "before", "after" }, order)
  end)

  it("propagates an awaited failure as an error through the real loop", function()
    local handle = task.run(function()
      task.await(function(resume)
        resume(false, "boom")
      end)
      return "unreached"
    end)
    local ok, err = task.block(handle, 1000)
    assert.is_true(handle.done)
    assert.is_false(ok)
    assert.is_true(tostring(err):find("boom", 1, true) ~= nil)
  end)

  it("cancel settles the task once as cancelled", function()
    local handle = task.run(function()
      task.sleep(10000) -- long; never completes on its own
      return "done"
    end)
    handle.cancel()
    assert.is_true(handle.done)
    assert.is_false(handle.ok)
    assert.equal("cancelled", handle.result)
  end)

  it("block returns on timeout for a task that never completes (no hang)", function()
    local handle = task.run(function()
      task.await(function(_resume) end) -- never resumes
      return "nope"
    end)
    task.block(handle, 80)
    assert.is_false(handle.done) -- timed out rather than hanging
    handle.cancel()
  end)
end)
