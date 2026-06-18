-- L3 integration test for liv.core (spec 0004, 0005). Runs inside real Vim
-- (+lua) and Neovim, exercising the seam primitives and bidirectional marshaling
-- — including the sharp edges: nested NIL in a list and empty-dict round-trip.
local core = require("liv.core")

describe("liv.core.is_nvim", function()
  it("is a boolean", function()
    assert.is_boolean(core.is_nvim)
  end)
end)

describe("liv.core.call", function()
  it("calls a vimscript function with scalar args", function()
    assert.equal(5, core.call("abs", -5))
  end)

  it("returns a list as a plain 1-based Lua table", function()
    assert.same({ 0, 1, 2 }, core.call("range", 3))
  end)

  it("round-trips a list argument (Lua table -> editor -> Lua table)", function()
    assert.same({ 3, 2, 1 }, core.call("reverse", core.list({ 1, 2, 3 })))
  end)

  it("round-trips a dict argument", function()
    assert.same({ "a" }, core.call("keys", core.dict({ a = 1 })))
  end)
end)

describe("liv.core.eval", function()
  it("evaluates a scalar expression", function()
    assert.equal(3, core.eval("1 + 2"))
  end)

  it("maps v:true / v:false to Lua booleans", function()
    assert.is_true(core.eval("v:true"))
    assert.is_false(core.eval("v:false"))
  end)

  it("maps v:null to core.NIL", function()
    assert.equal(core.NIL, core.eval("v:null"))
  end)
end)

describe("liv.core marshaling sharp edges", function()
  it("decodes a nested v:null inside a list as core.NIL (counted by length)", function()
    local got = core.eval("[1, v:null, 3]")
    assert.equal(3, #got)
    assert.equal(1, got[1])
    assert.equal(core.NIL, got[2])
    assert.equal(3, got[3])
  end)

  it("round-trips an empty dict as a dict, not a list", function()
    -- vimscript type(): 3 = List, 4 = Dict. An empty list would be 3.
    assert.equal(4, core.call("type", core.empty_dict()))
  end)

  it("round-trips an empty list as a list", function()
    assert.equal(3, core.call("type", {}))
  end)
end)

describe("liv.core.cmd", function()
  it("runs an ex command whose effect is observable via eval", function()
    core.cmd("let g:liv_test_marker = 42")
    assert.equal(42, core.eval("g:liv_test_marker"))
  end)
end)

describe("liv.core.marshaled", function()
  it("returns a callable whose args/result are marshaled (both editors)", function()
    local abs = core.marshaled(vim.fn.abs)
    assert.equal(5, abs(-5))
  end)

  it("round-trips a list through the marshaled callable", function()
    local reverse = core.marshaled(vim.fn.reverse)
    assert.same({ 3, 2, 1 }, reverse(core.list({ 1, 2, 3 })))
  end)

  it("memoizes per function reference (same wrapper returned)", function()
    assert.equal(core.marshaled(vim.fn.abs), core.marshaled(vim.fn.abs))
  end)

  if core.is_nvim then
    it("wraps the Neovim native API via a real symbol", function()
      local strwidth = core.marshaled(vim.api.nvim_strwidth)
      assert.equal(5, strwidth("hello"))
    end)
  end
end)
