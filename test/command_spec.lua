-- L3 integration test for liv.std.command (spec 0006), on both editors. Proves
-- a Lua handler is invoked with the command's args -- natively on Neovim, via the
-- Vim 9 Funcref dispatch on Vim.
local command = require("liv.std.command")
local core = require("liv.core")

describe("liv.std.command (L3)", function()
  it("defines a command that calls the Lua handler with its args", function()
    local got
    command.define("LivTestCmd", { nargs = "*" }, function(args)
      got = args
    end)
    core.cmd("LivTestCmd hello world")
    assert.equal("hello world", got)
    command.remove("LivTestCmd")
  end)

  it("defines a command with no opts (opts omitted)", function()
    local got
    command.define("LivTestCmdNoOpts", function(args)
      got = args
    end)
    core.cmd("LivTestCmdNoOpts hi")
    assert.equal("hi", got)
    command.remove("LivTestCmdNoOpts")
  end)

  it("remove deletes the command", function()
    command.define("LivTestCmd2", function() end)
    assert.equal(2, core.call("exists", ":LivTestCmd2")) -- defined
    command.remove("LivTestCmd2")
    assert.equal(0, core.call("exists", ":LivTestCmd2")) -- gone
  end)

  it("invokes the handler each time the command runs", function()
    local count = 0
    command.define("LivTestCmd3", { nargs = "0" }, function()
      count = count + 1
    end)
    core.cmd("LivTestCmd3")
    core.cmd("LivTestCmd3")
    assert.equal(2, count)
    command.remove("LivTestCmd3")
  end)

  it("returns a subscription whose off() removes the command", function()
    local sub = command.define("LivTestCmdSub", function() end)
    assert.equal(2, core.call("exists", ":LivTestCmdSub"))
    sub.off()
    assert.equal(0, core.call("exists", ":LivTestCmdSub"))
  end)

  it("off() is idempotent (calling it twice is a no-op)", function()
    local sub = command.define("LivTestCmdIdem", function() end)
    sub.off()
    sub.off()
    assert.equal(0, core.call("exists", ":LivTestCmdIdem"))
  end)

  it("wires a custom completion function that returns its candidates", function()
    local seen
    command.define("LivTestCmpl", {
      nargs = "*",
      complete = function(arglead, _cmdline, _cursorpos)
        seen = arglead
        -- customlist completers filter themselves (Vim does not filter for them).
        local out = {}
        for _, cand in ipairs({ "alpha", "beta", "gamma" }) do
          if cand:sub(1, #arglead) == arglead then
            out[#out + 1] = cand
          end
        end
        return out
      end,
    }, function() end)
    -- getcompletion drives the command's custom completion (customlist on Vim,
    -- the Lua complete callback on Neovim), exercising the real bridge.
    local result = core.call("getcompletion", "LivTestCmpl al", "cmdline")
    assert.equal("al", seen)
    assert.same({ "alpha" }, result)
    command.remove("LivTestCmpl")
  end)
end)
