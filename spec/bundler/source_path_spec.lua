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

  it("reads a sibling .deps.lua manifest and arbitrary files via read_raw", function()
    local fs2 = mockfs({
      ["/src/liv/std/_dispatch.lua"] = "DISPATCH",
      ["/src/liv/std/_dispatch.deps.lua"] = 'return { files = { "_dispatch.vim" } }',
      ["/src/liv/std/_dispatch.vim"] = "VIM9",
    })
    local r2 = path.resolver("/src", fs2)
    assert.same({ files = { "_dispatch.vim" } }, r2.manifest("liv.std._dispatch"))
    assert.equal("VIM9", r2.read_raw("liv/std/_dispatch.vim"))
    assert.is_nil(r2.manifest("liv.std.nomanifest"))
  end)
end)
