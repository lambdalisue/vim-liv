-- L1 self-test for the liv.tester.cli structured exit-code mapping (spec 0010,
-- Phase 3). `main()` cannot be driven end-to-end without editors, so the exit
-- decision is a pure function tested directly: 0 ok / 1 test failures / 2 usage
-- error / 4 no tests found.
local cli = require("liv.tester.cli")

describe("liv.tester.cli.exit_code", function()
  it("returns 0 when tests ran and none failed", function()
    assert.equal(0, cli.exit_code({ ran = true, failed = 0, usage_error = false }))
  end)

  it("returns 1 when at least one test failed", function()
    assert.equal(1, cli.exit_code({ ran = true, failed = 3, usage_error = false }))
  end)

  it("returns 2 on a usage error regardless of counts", function()
    assert.equal(2, cli.exit_code({ ran = false, failed = 0, usage_error = true }))
    assert.equal(2, cli.exit_code({ ran = true, failed = 5, usage_error = true }))
  end)

  it("returns 4 when no tests were found", function()
    assert.equal(4, cli.exit_code({ ran = false, failed = 0, usage_error = false }))
  end)
end)

describe("liv.tester.cli.default_reporter", function()
  it("is spec on a terminal and tap otherwise", function()
    assert.equal("spec", cli.default_reporter(true))
    assert.equal("tap", cli.default_reporter(false))
  end)
end)

describe("liv.tester.cli.parse_args verbosity", function()
  it("defaults verbose and quiet to false", function()
    local parsed = cli.parse_args({})
    assert.is_false(parsed.verbose)
    assert.is_false(parsed.quiet)
  end)

  it("flags --verbose and --quiet", function()
    assert.is_true(cli.parse_args({ "--verbose" }).verbose)
    assert.is_true(cli.parse_args({ "--quiet" }).quiet)
  end)
end)
