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

  it("prompt accepts a completion function without breaking the prompt", function()
    -- Vim-strong / Neovim-best-effort: on Vim the completion fn is wired to a
    -- customlist completion function via the dispatch and drives input(); on Neovim
    -- a Lua completion fn cannot be honored by the default vim.ui.input (its
    -- documented `completion` is a -complete= type STRING, and forwarding a Funcref
    -- to vim.fn.input raises E729), so it is not forwarded. Either way the entered
    -- text still reaches the handler — prompt itself always works.
    local got
    local completion = function(_lead)
      return { "alpha", "beta" }
    end
    if core.is_nvim then
      local orig = vim.ui.input
      local captured
      vim.ui.input = function(opts, on_confirm)
        captured = opts
        on_confirm("typed")
      end
      ui.prompt({ prompt = "name: ", completion = completion }, function(text)
        got = text
      end)
      vim.ui.input = orig
      -- A Lua completion fn is not forwarded on Neovim (it cannot be honored by the
      -- default vim.ui.input, which expects a -complete= type string).
      assert.is_nil(captured.completion)
    else
      core.call("feedkeys", core.eval([["typed\<CR>"]]), "t")
      ui.prompt({ prompt = "name: ", completion = completion }, function(text)
        got = text
      end)
    end
    assert.equal("typed", got)
  end)

  it("the Vim completion forwarder returns the candidates when invoked by name", function()
    -- Vim only: the dispatch builds a customlist completion function bound to the
    -- Lua completion handler. We invoke that function by NAME (as the editor would
    -- when completing) to verify the wiring delivers the candidates, without
    -- driving interactive Tab (which is not driveable headless). The same dispatch
    -- forwarder is what ui.prompt assigns to input()'s completion argument.
    if core.is_nvim then
      return
    end
    local dispatch = require("liv.std._dispatch")(core)
    local id, name = dispatch.register_complete(function(lead, _cmdline, _cursorpos)
      return { lead .. "alpha", lead .. "beta" }
    end)
    local candidates = core.call(name, "x", "", 0)
    assert.same({ "xalpha", "xbeta" }, candidates)
    dispatch.unregister(id)
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
