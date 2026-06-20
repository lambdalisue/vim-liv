-- L1 unit test for liv.generator option orchestration: split parsed Vim/Neovim
-- option defs into common / vim-only / nvim-only and emit the per-namespace
-- files (pure Lua; the bin downloads + parses, this decides what to write).
local generate = require("liv.generator.option.generate")

describe("liv.generator.option.generate", function()
  local files
  before_each(function()
    files = generate({ -- vim
      { name = "expandtab", type = "boolean", scope = "buffer" },
      { name = "vimonly", type = "number", scope = "global" },
    }, { -- nvim
      { name = "expandtab", type = "boolean", scope = "buffer" },
      { name = "nvimonly", type = "string", scope = "global" },
    })
  end)

  it("puts options present in both editors in the common module", function()
    local common = assert(load(files["lua/liv/std/option/_generated.lua"]))()
    assert.is_not_nil(common.expandtab)
    assert.is_nil(common.vimonly)
    assert.is_nil(common.nvimonly)
  end)

  it("puts vim-only options under option/vim", function()
    local vim = assert(load(files["lua/liv/std/option/vim/_generated.lua"]))()
    assert.is_not_nil(vim.vimonly)
    assert.is_nil(vim.expandtab)
  end)

  it("puts nvim-only options under option/nvim", function()
    local nvim = assert(load(files["lua/liv/std/option/nvim/_generated.lua"]))()
    assert.is_not_nil(nvim.nvimonly)
    assert.is_nil(nvim.expandtab)
  end)

  it("emits LuaLS annotation files per namespace with distinct classes", function()
    assert.is_true(
      files["lua/liv/std/option/_generated_annotations.lua"]:find("liv.std.option.Common", 1, true)
        ~= nil
    )
    assert.is_true(
      files["lua/liv/std/option/vim/_generated_annotations.lua"]:find("liv.std.option.Vim", 1, true)
        ~= nil
    )
    assert.is_true(
      files["lua/liv/std/option/nvim/_generated_annotations.lua"]:find(
        "liv.std.option.Nvim",
        1,
        true
      ) ~= nil
    )
  end)
end)
