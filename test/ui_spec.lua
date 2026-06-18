-- L3 integration test for liv.std.ui (spec 0006), on both editors. notify is
-- checked via the message history on both. For select/prompt the editors diverge
-- in how they can be driven headless: Vim's popup_menu / input() are driven with
-- feedkeys (real), while Neovim's vim.ui.select / vim.ui.input are the
-- user-overridable hooks (and block under headless), so they are stubbed — which
-- also verifies the backend forwards items/opts and maps the result to handler.
local ui = require("liv.std.ui")
local core = require("liv.core")

describe("liv.std.ui (L3)", function()
  it("notify records a message", function()
    ui.notify("liv_notify_probe", "warn")
    local msgs = core.call("execute", "messages")
    assert.is_not_nil(msgs:find("liv_notify_probe"))
  end)

  it("select invokes the handler with the chosen item", function()
    local chosen
    if core.is_nvim then
      local orig = vim.ui.select
      vim.ui.select = function(items, _opts, on_choice)
        on_choice(items[2], 2)
      end
      ui.select({ "a", "b", "c" }, { prompt = "pick" }, function(item, index)
        chosen = { item = item, index = index }
      end)
      vim.ui.select = orig
    else
      ui.select({ "a", "b", "c" }, { prompt = "pick" }, function(item, index)
        chosen = { item = item, index = index }
      end)
      core.call("feedkeys", core.eval([["\<CR>"]]), "x") -- select the current (first) item
    end
    assert.is_not_nil(chosen)
    assert.is_not_nil(chosen.item)
    assert.is_not_nil(chosen.index)
  end)

  it("prompt invokes the handler with the entered text", function()
    local got
    if core.is_nvim then
      local orig = vim.ui.input
      vim.ui.input = function(_opts, on_confirm)
        on_confirm("typed")
      end
      ui.prompt({ prompt = "name: " }, function(text)
        got = text
      end)
      vim.ui.input = orig
    else
      core.call("feedkeys", core.eval([["typed\<CR>"]]), "t") -- queued, consumed by input()
      ui.prompt({ prompt = "name: " }, function(text)
        got = text
      end)
    end
    assert.equal("typed", got)
  end)

  it("prompt handler receives nil when cancelled", function()
    -- Cancel (Esc) cannot be driven in headless `vim -es` (inputdialog blocks on
    -- Esc), so this asserts the cancel->nil mapping on Neovim, where vim.ui.input
    -- is a stubbable hook. The Vim backend maps inputdialog's cancelreturn
    -- sentinel to nil with the same structure (ui/_vim.lua).
    if not core.is_nvim then
      return
    end
    local called, value = false, "sentinel"
    local orig = vim.ui.input
    vim.ui.input = function(_opts, on_confirm)
      on_confirm(nil)
    end
    ui.prompt({ prompt = "name: " }, function(text)
      called, value = true, text
    end)
    vim.ui.input = orig
    assert.is_true(called)
    assert.is_nil(value)
  end)

  it("prompt accepts omitted opts", function()
    local got
    if core.is_nvim then
      local orig = vim.ui.input
      vim.ui.input = function(_opts, on_confirm)
        on_confirm("x")
      end
      ui.prompt(function(text)
        got = text
      end)
      vim.ui.input = orig
    else
      core.call("feedkeys", core.eval([["x\<CR>"]]), "t")
      ui.prompt(function(text)
        got = text
      end)
    end
    assert.equal("x", got)
  end)

  it("select handler receives nil when cancelled", function()
    -- popup_menu's Esc/cancel cannot be driven in headless `vim -es` (it blocks
    -- on the filter), so the cancel->nil mapping is asserted on Neovim via the
    -- stubbable vim.ui.select. The Vim backend maps a non-positive popup result
    -- to nil with the same structure (ui/_vim.lua).
    if not core.is_nvim then
      return
    end
    local called, value = false, "sentinel"
    local orig = vim.ui.select
    vim.ui.select = function(_items, _opts, on_choice)
      on_choice(nil, nil)
    end
    ui.select({ "a", "b" }, {}, function(item)
      called, value = true, item
    end)
    vim.ui.select = orig
    assert.is_true(called)
    assert.is_nil(value)
  end)
end)
