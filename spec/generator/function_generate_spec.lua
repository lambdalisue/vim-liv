-- L1 unit test for liv.generator function orchestration: split parsed Vim/Neovim
-- function entries into common / vim-only / nvim-only and emit one annotation
-- file per namespace (pure Lua).
local generate = require("liv.generator.function.generate")

describe("liv.generator.function.generate", function()
  local files
  before_each(function()
    files = generate(
      { -- vim
        { name = "getline", params = { { name = "lnum", optional = false } }, rettype = "string" },
        { name = "vimonly", params = {}, rettype = "integer" },
      },
      { -- nvim
        { name = "getline", params = { { name = "lnum", optional = false } }, rettype = "string" },
        { name = "nvimonly", params = {}, rettype = "integer" },
      }
    )
  end)

  it("puts common functions under function with the Common class", function()
    local f = files["lua/liv/std/function/_generated_annotations.lua"]
    assert.is_true(f:find("liv.std.function.Common", 1, true) ~= nil)
    assert.is_true(f:find("---@field getline", 1, true) ~= nil)
    assert.is_nil(f:find("vimonly", 1, true))
  end)

  it("puts vim-only functions under function/vim", function()
    local f = files["lua/liv/std/function/vim/_generated_annotations.lua"]
    assert.is_true(f:find("liv.std.function.Vim", 1, true) ~= nil)
    assert.is_true(f:find("---@field vimonly", 1, true) ~= nil)
    assert.is_nil(f:find("getline", 1, true))
  end)

  it("puts nvim-only functions under function/nvim", function()
    local f = files["lua/liv/std/function/nvim/_generated_annotations.lua"]
    assert.is_true(f:find("liv.std.function.Nvim", 1, true) ~= nil)
    assert.is_true(f:find("---@field nvimonly", 1, true) ~= nil)
  end)
end)
