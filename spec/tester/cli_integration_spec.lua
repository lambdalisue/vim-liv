-- L1 integration test for liv.tester.cli.main wiring the P5 workflow features:
-- config discovery + precedence, --list, --failed rerun, and init. Each case
-- builds a throwaway fixture project (its own spec/ + .liv-tester.lua) and drives
-- main() with a capturing writer, so no real editor is needed (L1 only; L3 is
-- skip-if-missing and not asserted here).
local cli = require("liv.tester.cli")

-- Build an isolated fixture project directory and return its path.
local function fixture()
  local dir = os.tmpname()
  os.remove(dir)
  os.execute("mkdir -p " .. dir .. "/spec")
  return dir
end

local function write(path, content)
  local fh = assert(io.open(path, "w"))
  fh:write(content)
  fh:close()
end

-- Run main() capturing its stdout into a string. `argv` is the token list. The
-- run's CWD-derived discovery is driven by `project`.
local function run(project, argv)
  local buf = {}
  local real = io.write
  io.write = function(...)
    for _, s in ipairs({ ... }) do
      buf[#buf + 1] = s
    end
  end
  local ok, code = pcall(cli.main, { root = ".", project = project, argv = argv })
  io.write = real
  assert(ok, code)
  return code, table.concat(buf)
end

describe("liv.tester.cli.main --list", function()
  it("prints candidate names without running bodies", function()
    local dir = fixture()
    write(
      dir .. "/spec/sample_spec.lua",
      [[describe("g", function()
        it("alpha", function() error("must not run") end)
        it("beta", function() error("must not run") end)
      end)]]
    )
    local code, out = run(dir, { "--list" })
    os.execute("rm -rf " .. dir)
    assert.equal(0, code)
    assert.is_not_nil(out:find("g alpha", 1, true))
    assert.is_not_nil(out:find("g beta", 1, true))
  end)
end)

describe("liv.tester.cli.main config precedence", function()
  it("discovers .liv-tester.lua and applies its default selector", function()
    local dir = fixture()
    -- The config narrows the run to tests tagged smoke.
    write(dir .. "/.liv-tester.lua", [[return { select = { "tag:smoke" } }]])
    write(
      dir .. "/spec/sample_spec.lua",
      [[describe("g", function()
        it("kept", { tags = { "smoke" } }, function() end)
        it("dropped", function() error("filtered out by config selector") end)
      end)]]
    )
    local code, out = run(dir, {})
    os.execute("rm -rf " .. dir)
    -- Only the smoke-tagged test ran (the other was filtered, so 0 failures).
    assert.equal(0, code)
    assert.is_not_nil(out:find("using config", 1, true))
    assert.is_not_nil(out:find("1 passed", 1, true))
  end)

  it("a config syntax error is a usage error (exit 2)", function()
    local dir = fixture()
    write(dir .. "/.liv-tester.lua", [[return { = }]])
    write(dir .. "/spec/sample_spec.lua", [[describe("g", function() it("a", function() end) end)]])
    local code = run(dir, {})
    os.execute("rm -rf " .. dir)
    assert.equal(2, code)
  end)
end)

describe("liv.tester.cli.main --failed rerun", function()
  it("after a failing run, --failed reruns only the failed test", function()
    local dir = fixture()
    write(
      dir .. "/spec/sample_spec.lua",
      [[describe("g", function()
        it("good", function() end)
        it("bad", function() error("boom") end)
      end)]]
    )
    -- First run: records the failure into .liv/last-run.lua.
    local code1 = run(dir, {})
    assert.equal(1, code1)
    -- Second run with --failed: only "g bad" is a candidate (still fails).
    local code2, out2 = run(dir, { "--failed" })
    os.execute("rm -rf " .. dir)
    assert.equal(1, code2)
    -- Exactly one test ran (the previously failing one); "good" was not a candidate.
    assert.is_not_nil(out2:find("0 passed, 1 failed", 1, true))
  end)

  it("persists the failed test's file:line origin in the state file", function()
    local dir = fixture()
    write(
      dir .. "/spec/sample_spec.lua",
      [[describe("g", function()
        it("bad", function() error("boom") end)
      end)]]
    )
    run(dir, {})
    local state = assert(loadfile(dir .. "/.liv/last-run.lua"))()
    os.execute("rm -rf " .. dir)
    assert.equal(1, #state.failures)
    assert.equal("g bad", state.failures[1].name)
    -- Origin captured at it() via debug.getinfo rides into the state file.
    assert.equal("string", type(state.failures[1].file))
    assert.equal("number", type(state.failures[1].line))
  end)

  it("--failed after a clean run reruns nothing", function()
    local dir = fixture()
    write(
      dir .. "/spec/sample_spec.lua",
      [[describe("g", function() it("ok", function() end) end)]]
    )
    local code1 = run(dir, {})
    assert.equal(0, code1)
    local code2, out2 = run(dir, { "--failed" })
    os.execute("rm -rf " .. dir)
    -- No candidates → L1 reports 0 passed, 0 failed.
    assert.equal(0, code2)
    assert.is_not_nil(out2:find("0 passed, 0 failed", 1, true))
  end)
end)

describe("liv.tester.cli.main init", function()
  it("scaffolds a config + example spec and returns 0", function()
    local dir = fixture()
    local code, out = run(dir, { "init" })
    assert.equal(0, code)
    assert.is_not_nil(out:find("created", 1, true))
    local cfg = assert(loadfile(dir .. "/.liv-tester.lua"))()
    assert.is_table(cfg)
    os.execute("rm -rf " .. dir)
  end)

  it("refuses to overwrite an existing config (exit 2)", function()
    local dir = fixture()
    write(dir .. "/.liv-tester.lua", [[return {}]])
    local code = run(dir, { "init" })
    os.execute("rm -rf " .. dir)
    assert.equal(2, code)
  end)
end)
