-- L1 unit test for liv.bundler.source.path with an in-memory fs. Pure, no editor.
local path = require("liv.bundler.source.path")

local function mockfs(files)
  return {
    exists = function(p)
      return files[p] ~= nil
    end,
    read = function(p)
      return files[p]
    end,
  }
end

describe("liv.bundler.source.path", function()
  local fs = mockfs({
    ["/src/liv/core.lua"] = "CORE",
    ["/src/liv/std/buffer/init.lua"] = "BUFFER",
  })
  local r = path.resolver("/src", fs)

  it("locates a plain X.lua module and reads it", function()
    assert.equal("liv/core.lua", r.locate("liv.core"))
    assert.equal("CORE", r.read("liv.core"))
  end)

  it("locates an X/init.lua module", function()
    assert.equal("liv/std/buffer/init.lua", r.locate("liv.std.buffer"))
    assert.equal("BUFFER", r.read("liv.std.buffer"))
  end)

  it("returns nil for an unresolvable module", function()
    assert.is_nil(r.locate("liv.nope"))
    assert.is_nil(r.read("liv.nope"))
  end)
end)
