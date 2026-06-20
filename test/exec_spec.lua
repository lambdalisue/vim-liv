-- L3 integration test for liv.std.exec (spec 0006), on both editors. exec runs a
-- block of vimscript through core.cmd: multiple lines run as multiple Ex commands,
-- and leading-backslash continuation lines are joined to the previous line per
-- Vim's continuation rule before running. Effects are asserted through core.eval.
local exec = require("liv.std.exec")
local core = require("liv.core")

describe("liv.std.exec (L3)", function()
  it("runs each line of a multi-line string as an Ex command", function()
    core.cmd("unlet! g:liv_exec_probe g:liv_exec_probe2")
    exec("let g:liv_exec_probe = 1\nlet g:liv_exec_probe2 = 2")
    assert.equal(1, core.eval("g:liv_exec_probe"))
    assert.equal(2, core.eval("g:liv_exec_probe2"))
  end)

  it("joins leading-backslash continuation lines onto the previous line", function()
    core.cmd("unlet! g:liv_exec_c")
    exec("let g:liv_exec_c =\n\\ 42")
    assert.equal(42, core.eval("g:liv_exec_c"))
  end)

  it("accepts an array of lines", function()
    core.cmd("unlet! g:liv_exec_a g:liv_exec_b")
    exec({ "let g:liv_exec_a = 10", "let g:liv_exec_b = 20" })
    assert.equal(10, core.eval("g:liv_exec_a"))
    assert.equal(20, core.eval("g:liv_exec_b"))
  end)

  it("joins continuation lines in an array form too", function()
    core.cmd("unlet! g:liv_exec_arr_c")
    exec({ "let g:liv_exec_arr_c =", "\\ 99" })
    assert.equal(99, core.eval("g:liv_exec_arr_c"))
  end)
end)
