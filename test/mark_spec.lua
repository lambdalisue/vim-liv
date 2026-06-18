-- L3 integration test for liv.std.mark (spec 0006), on both editors. The two
-- editors store decorations differently (extmarks vs text properties), so the
-- test counts liv's marks per editor and asserts the same place/remove/clear
-- lifecycle. The scratch buffer is fresh, so a total property count equals liv's
-- marks on the Vim side.
local mark = require("liv.std.mark")
local has = require("liv.has")
local core = require("liv.core")

local function count()
  local buf = core.call("bufnr", "")
  if core.is_nvim then
    local ns = vim.api.nvim_create_namespace("liv.std.mark")
    return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  end
  local last = core.call("line", "$")
  return #core.eval(string.format("prop_list(1, {'bufnr': %d, 'end_lnum': %d})", buf, last))
end

describe("liv.std.mark (L3)", function()
  before_each(function()
    core.cmd("enew!")
    core.call("setline", 1, core.list({ "alpha alpha", "beta beta" }))
  end)

  it("places a line highlight and returns an id", function()
    local id = mark.place(0, 1, { hl = "Search" })
    assert.equal("number", type(id))
    assert.equal(1, count())
    mark.remove(0, id)
    assert.equal(0, count())
  end)

  it("places virtual text when supported", function()
    assert.is_true(has("mark.virt_text"))
    local id = mark.place(0, 2, { virt_text = "<<note", virt_text_hl = "Comment" })
    assert.is_true(count() >= 1)
    mark.remove(0, id)
    assert.equal(0, count())
  end)

  it("clear removes every liv mark in the buffer", function()
    mark.place(0, 1, { hl = "Search" })
    mark.place(0, 2, { virt_text = "x" })
    assert.is_true(count() >= 2)
    mark.clear(0)
    assert.equal(0, count())
  end)

  it("highlights an intra-line column range", function()
    assert.is_true(has("mark.range"))
    local id = mark.range(0, { 1, 1 }, { 1, 5 }, { hl = "Search" })
    assert.equal("number", type(id))
    assert.is_true(count() >= 1)
    -- Assert the actual span, not just that a mark exists: {1,1}->{1,5} is the
    -- first five 1-based-inclusive byte columns. A regression that highlighted
    -- the whole line (or had an off-by-one) would still satisfy a count check.
    local buf = core.call("bufnr", "")
    if core.is_nvim then
      local ns = vim.api.nvim_create_namespace("liv.std.mark")
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
      assert.equal(0, marks[1][3]) -- start col, 0-based
      assert.equal(5, marks[1][4].end_col) -- end col, 0-based exclusive
    else
      local props = core.eval(string.format("prop_list(1, {'bufnr': %d})", buf))
      assert.equal(1, props[1].col) -- start col, 1-based
      assert.equal(5, props[1].length) -- byte length of the span
    end
    mark.remove(0, id)
    assert.equal(0, count())
  end)

  it("splits a multi-line range across its lines and removes it whole", function()
    core.cmd("enew!")
    core.call("setline", 1, core.list({ "first line", "middle", "last line" }))
    local id = mark.range(0, { 1, 4 }, { 3, 4 }, { hl = "Search" })
    -- Neovim keeps one extmark for the whole span; Vim splits into one property
    -- per line (three here). Either way clearing the single id drops everything.
    assert.is_true(count() >= 1)
    mark.remove(0, id)
    assert.equal(0, count())
  end)

  it("clears a multi-line range together with whole-line marks", function()
    mark.place(0, 1, { hl = "Search" })
    mark.range(0, { 1, 1 }, { 2, 4 }, { hl = "IncSearch" })
    assert.is_true(count() >= 2)
    mark.clear(0)
    assert.equal(0, count())
  end)

  it("lets a whole-line mark and a range coexist", function()
    local line_id = mark.place(0, 1, { hl = "Search" })
    local range_id = mark.range(0, { 2, 1 }, { 2, 4 }, { hl = "IncSearch" })
    assert.is_true(count() >= 2)
    mark.remove(0, range_id)
    assert.is_true(count() >= 1)
    mark.remove(0, line_id)
    assert.equal(0, count())
  end)
end)
