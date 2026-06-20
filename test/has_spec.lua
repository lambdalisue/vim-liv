-- L3 integration test for liv.std.has (spec 0006), on both editors. Asserts the
-- shape and the cross-editor contract: base features are available everywhere,
-- true-async fs is Neovim-only, and unknown keys report false.
local has = require("liv.std.has")
local core = require("liv.core")

describe("liv.std.has (L3)", function()
  it("reports base features available on both editors", function()
    assert.is_true(has("async"))
    assert.is_true(has("popup"))
    assert.is_true(has("mark"))
    assert.is_true(has("process.stream"))
  end)

  it("gates true-async filesystem to Neovim", function()
    assert.equal(core.is_nvim, has("fs.async"))
  end)

  it("reports virtual-text marks on both modern editors", function()
    -- Neovim always; Vim 9.x ships text-property virtual text.
    assert.is_true(has("mark.virt_text"))
  end)

  it("reports false (never errors) for an unknown feature", function()
    assert.is_false(has("totally.made.up"))
  end)

  it("gates fetch on an external curl/wget being installed", function()
    local fn = require("liv.std.function")
    local available = fn.executable("curl") == 1 or fn.executable("wget") == 1
    assert.equal(available, has("fetch"))
  end)
end)
