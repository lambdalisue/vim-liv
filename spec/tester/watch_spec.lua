-- L1 self-test for liv.tester._watch — the change-detection used by `--watch`.
-- Only the pure snapshot/diff logic is unit-tested (the polling loop drives a
-- real re-run and is best-effort, documented but not asserted headless).
local watch = require("liv.tester._watch")

describe("liv.tester._watch.changed", function()
  it("reports no change for identical snapshots", function()
    local a = { ["spec/a.lua"] = 100, ["spec/b.lua"] = 200 }
    local b = { ["spec/a.lua"] = 100, ["spec/b.lua"] = 200 }
    assert.is_false(watch.changed(a, b))
  end)

  it("reports a change when a file's mtime advances", function()
    local a = { ["spec/a.lua"] = 100 }
    local b = { ["spec/a.lua"] = 101 }
    assert.is_true(watch.changed(a, b))
  end)

  it("reports a change when a file is added", function()
    local a = { ["spec/a.lua"] = 100 }
    local b = { ["spec/a.lua"] = 100, ["spec/new.lua"] = 5 }
    assert.is_true(watch.changed(a, b))
  end)

  it("reports a change when a file is removed", function()
    local a = { ["spec/a.lua"] = 100, ["spec/gone.lua"] = 5 }
    local b = { ["spec/a.lua"] = 100 }
    assert.is_true(watch.changed(a, b))
  end)
end)

describe("liv.tester._watch.snapshot", function()
  it("maps each watched file to a numeric mtime", function()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p " .. dir .. "/lua " .. dir .. "/spec")
    local fh = assert(io.open(dir .. "/spec/x_spec.lua", "w"))
    fh:write("-- x\n")
    fh:close()
    local snap = watch.snapshot({ dir .. "/spec", dir .. "/lua" })
    os.execute("rm -rf " .. dir)
    local found, mtime = false, nil
    for path, t in pairs(snap) do
      if path:find("x_spec.lua", 1, true) then
        found, mtime = true, t
      end
    end
    assert.is_true(found)
    assert.equal("number", type(mtime))
  end)
end)
