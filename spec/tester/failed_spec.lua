-- L1 self-test for liv.tester._failed — persisting the last run's failures and
-- replaying only them on `--failed` (spec 0010).
local failed = require("liv.tester._failed")

describe("liv.tester._failed.save / load", function()
  it("round-trips a list of failure names through the state file", function()
    local path = os.tmpname()
    failed.save(path, {
      { name = "group does a thing", file = "spec/a_spec.lua", line = 10 },
      { name = "group does another (edge.case)", file = "spec/a_spec.lua", line = 20 },
    })
    local loaded = failed.load(path)
    os.remove(path)
    assert.equal(2, #loaded)
    assert.equal("group does a thing", loaded[1].name)
    assert.equal("group does another (edge.case)", loaded[2].name)
  end)

  it("load returns an empty list when the state file is absent", function()
    local loaded = failed.load(os.tmpname() .. "-nope")
    assert.same({}, loaded)
  end)

  it("preserves names containing magic pattern characters verbatim", function()
    local path = os.tmpname()
    failed.save(path, { { name = "a-b (c.d) %x [e]" } })
    local loaded = failed.load(path)
    os.remove(path)
    assert.equal("a-b (c.d) %x [e]", loaded[1].name)
  end)
end)

describe("liv.tester._failed.filter (exact full-title membership)", function()
  it("matches only the exact names from the failed set", function()
    local filter = failed.filter({ "group alpha", "group beta-gamma" })
    assert.is_true(filter("group alpha", {}))
    assert.is_true(filter("group beta-gamma", {}))
    assert.is_false(filter("group alphabet", {}))
    assert.is_false(filter("group", {}))
  end)

  it("treats magic characters literally (not as Lua patterns)", function()
    local filter = failed.filter({ "does (x.y) work" })
    assert.is_true(filter("does (x.y) work", {}))
    -- A pattern-based filter would also match this; exact membership must not.
    assert.is_false(filter("does (xZy) work", {}))
  end)

  it("an empty failed set matches nothing", function()
    local filter = failed.filter({})
    assert.is_false(filter("anything", {}))
  end)
end)

describe("liv.tester._failed.collect_l3_names", function()
  it("extracts FAIL names from a child result body", function()
    local body = table.concat({
      "RESULT\t1\t2\t0",
      "FAIL\ttest one failed",
      "  traceback line",
      "FAIL\ttest two (edge) failed",
      "  more traceback",
    }, "\n")
    local names = failed.collect_l3_names(body)
    assert.same({ "test one failed", "test two (edge) failed" }, names)
  end)

  it("returns an empty list for a body with no FAIL lines", function()
    assert.same({}, failed.collect_l3_names("RESULT\t3\t0\t0\n"))
  end)
end)
