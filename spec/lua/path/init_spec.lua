-- L1 unit test for path flavour selection (spec 0006).
local path = require("liv.lua.path")
local posix = require("liv.lua.path.posix")
local unc = require("liv.lua.path.unc")

describe("liv.lua.path default selection", function()
  it("exposes both flavours explicitly", function()
    assert.equal(posix, path.posix)
    assert.equal(unc, path.unc)
  end)

  it("defaults to the platform separator", function()
    assert.equal(package.config:sub(1, 1), path.sep)
  end)

  it("delegates API calls to the default flavour", function()
    local default = package.config:sub(1, 1) == "\\" and unc or posix
    assert.equal(default.join("a", "b"), path.join("a", "b"))
  end)
end)
