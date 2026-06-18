-- L3 integration test for liv.std.process (spec 0006/0007). Spawns real
-- processes on both editors and drives them to completion with task.block.
local process = require("liv.std.process")
local task = require("liv.std.task")

describe("liv.std.process (L3)", function()
  it("runs a command and captures stdout and exit code", function()
    local handle = task.run(function()
      return process.system({ "printf", "hello world" })
    end)
    local ok, res = task.block(handle, 3000)
    assert.is_true(handle.done)
    assert.is_true(ok)
    assert.equal(0, res.code)
    assert.equal("hello world", res.stdout)
  end)

  it("captures a nonzero exit code", function()
    local handle = task.run(function()
      return process.system({ "false" })
    end)
    task.block(handle, 3000)
    assert.is_true(handle.done)
    assert.equal(1, handle.result.code)
  end)

  it("captures stderr separately", function()
    local handle = task.run(function()
      return process.system({ "sh", "-c", "printf oops >&2" })
    end)
    task.block(handle, 3000)
    assert.equal("oops", handle.result.stderr)
    assert.equal("", handle.result.stdout)
  end)

  it("cancelling the task kills the process", function()
    local handle = task.run(function()
      return process.system({ "sleep", "5" })
    end)
    -- pump briefly so the process actually starts, then cancel
    task.block(task.run(function()
      task.sleep(50)
      return true
    end), 1000)
    handle.cancel()
    assert.is_true(handle.done)
    assert.is_false(handle.ok)
    assert.equal("cancelled", handle.result)
  end)
end)

-- Pump the editor event loop (so job callbacks fire) until `ready()` or timeout.
local function pump_until(ready)
  task.block(
    task.run(function()
      for _ = 1, 200 do
        if ready() then
          break
        end
        task.sleep(20)
      end
      return true
    end),
    5000
  )
end

describe("liv.std.process.open (L3 streaming)", function()
  it("delivers stdout one line per on_stdout call", function()
    local lines = {}
    local exited = false
    local exit_code
    local handle = process.open({ "bash", "-c", 'printf "a\\nb\\nc\\n"' }, {
      on_stdout = function(line)
        lines[#lines + 1] = line
      end,
      on_exit = function(result)
        exited = true
        exit_code = result.code
      end,
    })
    assert.is_table(handle)
    pump_until(function()
      return exited
    end)
    assert.is_true(exited)
    assert.equal(0, exit_code)
    assert.equal("a,b,c", table.concat(lines, ","))
  end)

  it("round-trips written data through a child's stdout and kill() stops it", function()
    local lines = {}
    local exited = false
    local handle = process.open({ "cat" }, {
      on_stdout = function(line)
        lines[#lines + 1] = line
      end,
      on_exit = function()
        exited = true
      end,
    })
    handle.write("hello\n")
    pump_until(function()
      return #lines >= 1
    end)
    assert.equal("hello", lines[1])
    assert.is_false(exited)

    handle.kill()
    pump_until(function()
      return exited
    end)
    assert.is_true(exited)
  end)

  it("reports streaming support on both editors", function()
    local has = require("liv.has")
    assert.is_true(has("process.stream"))
  end)
end)
