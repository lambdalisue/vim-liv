-- L3 integration test for liv.std.variable (spec 0006). Round-trips arbitrary values
-- through real variable APIs on both editors -- including the Vim global-set
-- json path and list/dict marshaling. Scopes are sub-tables (var.g/b/w/t).
local var = require("liv.std.variable")
local core = require("liv.core")

describe("liv.std.variable (L3)", function()
  it("global scope round-trips scalars, lists, and dicts", function()
    var.g.set("liv_t_num", 42)
    assert.equal(42, var.g.get("liv_t_num"))

    var.g.set("liv_t_str", "hello")
    assert.equal("hello", var.g.get("liv_t_str"))

    var.g.set("liv_t_list", core.list({ 1, 2, 3 }))
    assert.same({ 1, 2, 3 }, var.g.get("liv_t_list"))

    var.g.set("liv_t_dict", core.dict({ a = 1, b = 2 }))
    assert.same({ a = 1, b = 2 }, var.g.get("liv_t_dict"))
  end)

  it("buffer scope round-trips a value", function()
    var.b.set("liv_b", "buf-value")
    assert.equal("buf-value", var.b.get("liv_b"))
  end)

  it("window scope round-trips a value", function()
    var.w.set("liv_w", 7)
    assert.equal(7, var.w.get("liv_w"))
  end)

  it("tab scope round-trips a value", function()
    var.t.set("liv_tb", "tab-value")
    assert.equal("tab-value", var.t.get("liv_tb"))
  end)

  it("a mistyped scope is a plain nil index, not a silent runtime miss", function()
    assert.is_nil(var.bogus)
  end)

  it("an absent variable returns nil on every scope on both editors", function()
    -- A missing VALUE is nil (not an error, not Vim's empty-string default).
    assert.is_nil(var.g.get("liv_absent_global_xyz"))
    assert.is_nil(var.b.get("liv_absent_buffer_xyz"))
    assert.is_nil(var.w.get("liv_absent_window_xyz"))
    assert.is_nil(var.t.get("liv_absent_tab_xyz"))
    assert.is_nil(var.v.get("liv_absent_vvar_xyz"))
  end)

  it("an empty-string value is distinct from absent", function()
    var.b.set("liv_b_empty", "")
    assert.equal("", var.b.get("liv_b_empty"))
  end)

  it("v: scope reads editor variables", function()
    -- v:count is always present (0 outside a count context); reading it must not
    -- raise and must yield a number.
    assert.is_number(var.v.get("count"))
  end)

  it("v: scope set round-trips a writable v: var", function()
    var.v.set("errmsg", "liv-vvar-test")
    assert.equal("liv-vvar-test", var.v.get("errmsg"))
  end)
end)
