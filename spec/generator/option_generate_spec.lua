-- L1 unit test for liv.generator option orchestration: split parsed Vim/Neovim
-- option defs into common / vim-only / nvim-only and emit the per-namespace
-- files (pure Lua; the bin downloads + parses, this decides what to write).
local generate = require("liv.generator.option.generate")

describe("liv.generator.option.generate", function()
  local files
  before_each(function()
    files = generate({ -- vim
      { name = "expandtab", type = "boolean", scope = "buffer" },
      { name = "vimbool", type = "boolean", scope = "global" },
      { name = "vimnumber", type = "number", scope = "global" },
    }, { -- nvim
      { name = "expandtab", type = "boolean", scope = "buffer" },
      { name = "nvimbool", type = "boolean", scope = "global" },
    })
  end)

  it("puts boolean options present in both editors in the common runtime set", function()
    local common = assert(load(files["lua/liv/std/option/_generated.lua"]))()
    assert.equal(true, common.expandtab)
    assert.is_nil(common.vimbool)
    assert.is_nil(common.nvimbool)
  end)

  it("puts vim-only boolean options under option/vim (non-boolean dropped)", function()
    local vim = assert(load(files["lua/liv/std/option/vim/_generated.lua"]))()
    assert.equal(true, vim.vimbool)
    assert.is_nil(vim.expandtab)
    -- a vim-only NON-boolean option is absent from the slim runtime set
    assert.is_nil(vim.vimnumber)
  end)

  it("puts nvim-only boolean options under option/nvim", function()
    local nvim = assert(load(files["lua/liv/std/option/nvim/_generated.lua"]))()
    assert.equal(true, nvim.nvimbool)
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
