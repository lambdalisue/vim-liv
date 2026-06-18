-- L3 integration test for liv.std.tabpage (spec 0006), on both editors.
local tabpage = require("liv.std.tabpage")
local core = require("liv.core")

describe("liv.std.tabpage (L3)", function()
  before_each(function()
    core.cmd("silent! tabonly")
  end)

  it("current returns a tabpage handle", function()
    assert.is_number(tabpage.current())
  end)

  it("all lists the tabpages", function()
    assert.equal(1, #tabpage.all())
    core.cmd("tabnew")
    assert.equal(2, #tabpage.all())
  end)

  it("windows lists the windows of a tabpage", function()
    assert.is_true(#tabpage.windows(0) >= 1)
    assert.is_number(tabpage.windows(tabpage.current())[1])
  end)

  it("windows raises a uniform liv error on an invalid tabpage on both editors", function()
    -- An invalid handle passed to an operation must fail loudly and identically
    -- on both editors, not leak an opaque Lua/native error.
    local ok, err = pcall(tabpage.windows, 999999)
    assert.is_false(ok)
    assert.is_true(
      tostring(err):find("liv.std.tabpage: invalid tabpage id", 1, true) ~= nil,
      "expected liv-branded invalid-tabpage error, got: " .. tostring(err)
    )
  end)
end)
