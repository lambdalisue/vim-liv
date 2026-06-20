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
    task.block(
      task.run(function()
        task.sleep(50)
        return true
      end),
      1000
    )
    handle.cancel()
    assert.is_true(handle.done)
    assert.is_false(handle.ok)
    assert.equal("cancelled", handle.result)
  end)

  it("runs the child in opts.cwd", function()
    -- /tmp and /var are symlinks on macOS, so canonicalize both sides: compare
    -- the child's physical cwd (pwd -P) against the resolved temp dir.
    local dir = vim.fn.resolve(vim.fn.fnamemodify(vim.fn.tempname(), ":h"))
    local handle = task.run(function()
      return process.system({ "sh", "-c", "pwd -P" }, { cwd = dir })
    end)
    task.block(handle, 3000)
    assert.equal(0, handle.result.code)
    assert.equal(dir, (handle.result.stdout:gsub("%s+$", "")))
  end)

  it("extends the environment with opts.env", function()
    -- Echo both a parent var ($HOME) and the injected one: a surviving $HOME
    -- proves env EXTENDS rather than REPLACES the parent environment.
    local handle = task.run(function()
      return process.system({ "sh", "-c", "echo $HOME:$LIV_PROC_ENV" }, {
        env = { LIV_PROC_ENV = "proc_probe" },
      })
    end)
    task.block(handle, 3000)
    assert.equal(0, handle.result.code)
    local home, probe = handle.result.stdout:match("^(.-):(.-)%s*$")
    assert.is_true(home ~= nil and home ~= "")
    assert.equal("proc_probe", probe)
  end)
end)

describe("liv.std.process.run (L3 sync one-shot)", function()
  it("runs a command to completion synchronously without an async context", function()
    local r = process.run({ "sh", "-c", "echo sync_probe" })
    assert.equal(0, r.code)
    assert.equal("sync_probe", (r.stdout:gsub("%s+$", "")))
  end)

  it("honours cwd and env synchronously", function()
    local dir = vim.fn.resolve(vim.fn.fnamemodify(vim.fn.tempname(), ":h"))
    local r = process.run({ "sh", "-c", "pwd -P; echo $LIV_PROC_ENV" }, {
      cwd = dir,
      env = { LIV_PROC_ENV = "run_probe" },
    })
    assert.equal(0, r.code)
    local cwd, probe = r.stdout:match("^(.-)\n(.-)%s*$")
    assert.equal(dir, cwd)
    assert.equal("run_probe", probe)
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

  it("opens the streaming child in opts.cwd with opts.env", function()
    local dir = vim.fn.resolve(vim.fn.fnamemodify(vim.fn.tempname(), ":h"))
    local lines = {}
    local exited = false
    process.open({ "sh", "-c", 'pwd -P; echo "$HOME:$LIV_PROC_ENV"' }, {
      cwd = dir,
      env = { LIV_PROC_ENV = "open_probe" },
      on_stdout = function(line)
        lines[#lines + 1] = line
      end,
      on_exit = function()
        exited = true
      end,
    })
    pump_until(function()
      return exited
    end)
    assert.is_true(exited)
    assert.equal(dir, lines[1])
    -- A surviving $HOME proves env EXTENDS rather than REPLACES on the streaming
    -- path too (jobstart on nvim vs job_start on Vim), matching system/run.
    local home, probe = lines[2]:match("^(.-):(.-)$")
    assert.is_true(home ~= nil and home ~= "")
    assert.equal("open_probe", probe)
  end)

  it("kill() terminates a long-running child that reads stdin forever", function()
    local exited = false
    local handle = process.open({ "cat" }, {
      on_stdout = function() end,
      on_exit = function()
        exited = true
      end,
    })
    -- cat blocks on stdin indefinitely; kill must make on_exit fire.
    assert.is_false(exited)
    handle.kill()
    pump_until(function()
      return exited
    end)
    assert.is_true(exited)
  end)

  it("reports streaming support on both editors", function()
    local has = require("liv.std.has")
    assert.is_true(has("process.stream"))
  end)
end)
