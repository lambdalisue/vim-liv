-- L1 unit test for the editor-agnostic async runner (spec 0007).
-- Drives coroutines synchronously with a fake, drainable schedule — no editor.
local runner = require("liv.lua.async.runner")

-- A deterministic schedule: queue thunks, drain them on demand.
local function make_schedule()
  local queue = {}
  local function schedule(fn)
    queue[#queue + 1] = fn
  end
  local function drain()
    while queue[1] do
      table.remove(queue, 1)()
    end
  end
  return schedule, drain
end

describe("runner.run + await", function()
  it("resolves with the async function's return value", function()
    local schedule, drain = make_schedule()
    local got
    runner.run(function()
      local x = runner.await(function(resume)
        resume(true, 42)
      end)
      return x + 1
    end, {
      schedule = schedule,
      on_done = function(ok, v)
        got = { ok = ok, v = v }
      end,
    })
    drain()
    assert.is_true(got.ok)
    assert.equal(43, got.v)
  end)

  it("awaits several tasks in sequence", function()
    local schedule, drain = make_schedule()
    local got
    runner.run(function()
      local a = runner.await(function(resume)
        resume(true, 2)
      end)
      local b = runner.await(function(resume)
        resume(true, 3)
      end)
      return a * b
    end, { schedule = schedule, on_done = function(_, v)
      got = v
    end })
    drain()
    assert.equal(6, got)
  end)

  it("propagates a task failure as a Lua error", function()
    local schedule, drain = make_schedule()
    local got
    runner.run(function()
      runner.await(function(resume)
        resume(false, "boom")
      end)
    end, { schedule = schedule, on_done = function(ok, err)
      got = { ok = ok, err = err }
    end })
    drain()
    assert.is_false(got.ok)
    assert.is_true(tostring(got.err):find("boom", 1, true) ~= nil)
  end)

  it("reports a Lua error thrown inside the async function", function()
    local schedule, drain = make_schedule()
    local got
    runner.run(function()
      error("explode")
    end, { schedule = schedule, on_done = function(ok, err)
      got = { ok = ok, err = err }
    end })
    drain()
    assert.is_false(got.ok)
    assert.is_true(tostring(got.err):find("explode", 1, true) ~= nil)
  end)

  it("can recover from a failed await with pcall", function()
    local schedule, drain = make_schedule()
    local got
    runner.run(function()
      local ok, err = pcall(function()
        runner.await(function(resume)
          resume(false, "nope")
        end)
      end)
      return ok, err
    end, { schedule = schedule, on_done = function(_, v)
      got = v
    end })
    drain()
    assert.is_false(got)
  end)
end)

describe("runner.wrap", function()
  it("turns a callback-style function into an awaitable", function()
    local schedule, drain = make_schedule()
    local function delayed_add(a, b, cb)
      cb(a + b)
    end
    local add = runner.wrap(delayed_add)
    local got
    runner.run(function()
      return add(2, 3)
    end, { schedule = schedule, on_done = function(_, v)
      got = v
    end })
    drain()
    assert.equal(5, got)
  end)
end)

describe("runner cancellation", function()
  it("cancels a pending task and reports 'cancelled' once", function()
    local schedule, drain = make_schedule()
    local resume_later, canceler_called, calls = nil, false, {}
    local handle = runner.run(function()
      return runner.await(function(resume)
        resume_later = resume
        return function()
          canceler_called = true
        end
      end)
    end, { schedule = schedule, on_done = function(ok, v)
      calls[#calls + 1] = { ok = ok, v = v }
    end })
    drain() -- starts the coroutine; task stores resume and returns a canceler

    handle.cancel()
    assert.equal(1, #calls)
    assert.is_false(calls[1].ok)
    assert.equal("cancelled", calls[1].v)
    assert.is_true(canceler_called)

    -- A late resume after cancellation is ignored (no second on_done).
    resume_later(true, 99)
    drain()
    assert.equal(1, #calls)
  end)

  it("ignores cancel() after the run has already completed", function()
    local schedule, drain = make_schedule()
    local calls = {}
    local handle = runner.run(function()
      return runner.await(function(resume)
        resume(true, 7)
      end)
    end, { schedule = schedule, on_done = function(ok, v)
      calls[#calls + 1] = { ok = ok, v = v }
    end })
    drain() -- runs to completion: on_done(true, 7)
    assert.equal(1, #calls)
    assert.is_true(calls[1].ok)

    -- Defensive cleanup cancel after completion must not fire on_done again.
    handle.cancel()
    assert.equal(1, #calls)
  end)
end)
