-- L1 unit test for liv.bundler.list. Pure, no editor.
local list = require("liv.bundler.list")

describe("liv.bundler.list.discover", function()
  it("maps lua files to bundle-able modules, skipping internals/dev/manifests", function()
    local mods = list.discover({
      "liv/core.lua",
      "liv/std/buffer/init.lua",
      "liv/std/buffer/_nvim.lua", -- backend -> skip
      "liv/std/buffer/_vim.lua", -- backend -> skip
      "liv/std/_dispatch.lua", -- internal -> skip
      "liv/std/_dispatch.deps.lua", -- manifest -> skip
      "liv/lua/async/init.lua",
      "liv/bundler/cli.lua", -- dev tool -> skip
      "liv/tester/init.lua", -- dev tool -> skip
      "myplugin/foo.lua", -- not liv -> skip
    })
    assert.same({ "liv.core", "liv.lua.async", "liv.std.buffer" }, mods)
  end)
end)

describe("liv.bundler.list.list", function()
  it("tags each discovered module bundled or not", function()
    local l = list.list({ "liv/core.lua", "liv/std/buffer/init.lua" }, { ["liv.core"] = true })
    assert.same({
      { name = "liv.core", bundled = true },
      { name = "liv.std.buffer", bundled = false },
    }, l)
  end)
end)
