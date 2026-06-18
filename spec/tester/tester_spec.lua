-- L1 self-test for the liv.tester assertion library (spec 0010).
-- Exercises the assertion functions directly (no nested run), so it does not
-- perturb the surrounding suite's pass/fail counts.
local tester = require("liv.tester")
local A = tester.assert

describe("liv.tester assertions", function()
  it("equal accepts equals and rejects differences", function()
    A.equal(1, 1)
    A.has_error(function()
      A.equal(1, 2)
    end)
  end)

  it("same does a deep comparison", function()
    A.same({ a = { 1, 2 } }, { a = { 1, 2 } })
    A.has_error(function()
      A.same({ 1, 2 }, { 1, 3 })
    end)
  end)

  it("has_error matches a substring of the message", function()
    A.has_error(function()
      error("boom: detail")
    end, "boom")
  end)

  it("is_true / is_false are strict", function()
    A.is_true(true)
    A.is_false(false)
    A.has_error(function()
      A.is_true(1)
    end)
  end)
end)
