-- L1 self-test for liv.tester._init — the `liv-tester init` scaffold (spec 0010).
local scaffold = require("liv.tester._init")

local function tmpdir()
  local base = os.tmpname()
  os.remove(base)
  os.execute("mkdir -p " .. base)
  return base
end

describe("liv.tester._init.run", function()
  it("writes a .liv-tester.lua and an example spec into an empty project", function()
    local dir = tmpdir()
    local result = scaffold.run(dir)
    assert.is_true(result.ok)
    -- The config file exists and returns a table.
    local cfg = assert(loadfile(dir .. "/.liv-tester.lua"))()
    assert.is_table(cfg)
    -- An example spec exists under spec/.
    local fh = io.open(dir .. "/spec/example_spec.lua", "r")
    assert.is_not_nil(fh)
    if fh then
      fh:close()
    end
    os.execute("rm -rf " .. dir)
  end)

  it("refuses to clobber an existing .liv-tester.lua", function()
    local dir = tmpdir()
    local fh = assert(io.open(dir .. "/.liv-tester.lua", "w"))
    fh:write("return { reporter = 'keep-me' }\n")
    fh:close()
    local result = scaffold.run(dir)
    assert.is_false(result.ok)
    -- The original config is untouched.
    local cfg = assert(loadfile(dir .. "/.liv-tester.lua"))()
    assert.equal("keep-me", cfg.reporter)
    os.execute("rm -rf " .. dir)
  end)

  it("the generated example spec loads and registers tests", function()
    local dir = tmpdir()
    scaffold.run(dir)
    local tester = require("liv.tester")
    local t = tester.new()
    -- Install the generated spec into a hermetic registry and run it.
    local chunk = assert(loadfile(dir .. "/spec/example_spec.lua"))
    local env = setmetatable({
      describe = t.describe,
      it = t.it,
      assert = tester.assert,
    }, { __index = _G })
    setfenv(chunk, env)
    chunk()
    local passed, failed = t.run()
    assert.is_true(passed > 0)
    assert.equal(0, failed)
    os.execute("rm -rf " .. dir)
  end)
end)
