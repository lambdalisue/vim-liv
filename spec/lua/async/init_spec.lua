-- L1 unit test for the liv.lua.async facade (spec 0007).
local async = require("liv.lua.async")
local runner = require("liv.lua.async.runner")

describe("liv.lua.async", function()
  it("re-exports the pure engine's public functions", function()
    assert.equal(runner.await, async.await)
    assert.equal(runner.wrap, async.wrap)
    assert.equal(runner.run, async.run)
  end)

  it("runs an async function with an injected schedule", function()
    local queue = {}
    local function schedule(fn)
      queue[#queue + 1] = fn
    end
    local got
    async.run(function()
      return async.await(function(resume)
        resume(true, 21)
      end) * 2
    end, { schedule = schedule, on_done = function(_, v)
      got = v
    end })
    while queue[1] do
      table.remove(queue, 1)()
    end
    assert.equal(42, got)
  end)
end)
