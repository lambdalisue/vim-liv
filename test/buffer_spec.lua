-- L3 integration test for liv.std.buffer (spec 0006). Runs the real backend on
-- both editors and asserts identical Lua values, covering the index translation
-- and set_lines length changes (the asymmetric case on Vim).
local buffer = require("liv.std.buffer")
local core = require("liv.core")

describe("liv.std.buffer (L3)", function()
  before_each(function()
    core.cmd("enew!")
    core.call("setline", 1, core.list({ "one", "two", "three" }))
  end)

  it("lines reads a 1-based inclusive range", function()
    assert.same({ "one", "two" }, buffer.lines(0, 1, 2))
    assert.same({ "two", "three" }, buffer.lines(0, 2, 3))
    assert.same({ "two" }, buffer.lines(0, 2, 2))
  end)

  it("count returns the number of lines", function()
    assert.equal(3, buffer.count(0))
  end)

  it("set_lines replaces a range with the same number of lines", function()
    buffer.set_lines(0, 2, 2, { "TWO" })
    assert.same({ "one", "TWO", "three" }, buffer.lines(0, 1, 3))
  end)

  it("set_lines replaces a range with more lines", function()
    buffer.set_lines(0, 2, 2, { "a", "b" })
    assert.equal(4, buffer.count(0))
    assert.same({ "one", "a", "b", "three" }, buffer.lines(0, 1, 4))
  end)

  it("set_lines replaces a range with fewer lines", function()
    buffer.set_lines(0, 1, 2, { "X" })
    assert.equal(2, buffer.count(0))
    assert.same({ "X", "three" }, buffer.lines(0, 1, 2))
  end)

  it("set_lines can append after the last line", function()
    buffer.set_lines(0, 4, 3, { "four" }) -- first=count+1, last<first: pure insert at end
    assert.same({ "one", "two", "three", "four" }, buffer.lines(0, 1, 4))
  end)
end)

describe("liv.std.buffer lifecycle (L3)", function()
  it("valid reports whether a buffer exists", function()
    assert.is_true(buffer.valid(0)) -- current buffer
    assert.is_false(buffer.valid(999999))
  end)

  it("create returns a new valid buffer; wipe invalidates it", function()
    local b = buffer.create({})
    assert.is_number(b)
    assert.is_true(buffer.valid(b))
    buffer.wipe(b)
    assert.is_false(buffer.valid(b))
  end)

  it("create accepts a name and name() reads it back", function()
    -- name() returns the editor's own buffer name; absolute-path canonicalization
    -- can differ (e.g. /tmp -> /private/tmp), so assert on the path we set.
    local b = buffer.create({ name = "/tmp/liv_buffer_name_test.txt" })
    assert.is_true(buffer.name(b):find("liv_buffer_name_test%.txt$") ~= nil)
    buffer.wipe(b)
  end)

  it("create reuses an existing buffer of the same name on both editors", function()
    -- One contract: a named create returns the existing buffer of that name if one
    -- exists (reuse), else makes a new one. Vim's bufadd reuses; Neovim must look
    -- up the name first instead of raising E95.
    local name = "/tmp/liv_buffer_create_reuse.txt"
    local first = buffer.create({ name = name })
    local second = buffer.create({ name = name })
    assert.equal(first, second)
    buffer.wipe(first)
  end)

  it("a fresh buffer can be written and read like any other", function()
    local b = buffer.create({})
    buffer.set_lines(b, 1, buffer.count(b), { "hello", "world" })
    assert.same({ "hello", "world" }, buffer.lines(b, 1, buffer.count(b)))
    buffer.wipe(b)
  end)

  it("ops raise the same liv error on an invalid buffer on both editors", function()
    -- Vim's getbufline/bufname/getbufinfo/setbufline silently return []/""/fail
    -- on an invalid buffer where Neovim's native API raises; liv makes both raise
    -- identically (the failure is no longer editor-dependent).
    local msg = "liv.std.buffer: invalid buffer id"
    assert.has_error(function()
      buffer.lines(999999, 1, 1)
    end, msg)
    assert.has_error(function()
      buffer.name(999999)
    end, msg)
    assert.has_error(function()
      buffer.count(999999)
    end, msg)
    assert.has_error(function()
      buffer.set_lines(999999, 1, 1, { "x" })
    end, msg)
    -- wipe of an already-gone buffer is a no-op (lenient) on both editors: a bare
    -- call must not raise.
    buffer.wipe(999999)
  end)
end)

describe("liv.std.buffer.with (L3)", function()
  before_each(function()
    -- Scope away from a MODIFIED current buffer on purpose: this is the realistic
    -- case (you are editing a buffer and want to act on another), and on Vim a
    -- modified current buffer would block a plain no-bang `:buffer` switch — so
    -- this pins that `with` keeps the abandoned buffer (via `hide`).
    core.cmd("enew!")
    core.call("setline", 1, core.list({ "dirty" }))
  end)

  it("runs fn with buf as the current buffer, then restores the previous one", function()
    local a = core.call("bufnr", "%")
    local b = buffer.create({})
    local inside
    buffer.with(b, function()
      inside = core.call("bufnr", "%")
      -- Modify b inside the scope: this leaves b dirty so the switch BACK is also
      -- from a modified buffer (exercising `hide` on the restore, not just the
      -- switch-in), and lets us assert the edit round-tripped.
      buffer.set_lines(b, 1, buffer.count(b), { "written inside with" })
    end)
    assert.equal(b, inside) -- fn saw b as current
    assert.equal(a, core.call("bufnr", "%")) -- previous buffer restored after
    assert.same({ "written inside with" }, buffer.lines(b, 1, buffer.count(b))) -- edit persisted
    buffer.wipe(b)
  end)

  it("returns fn's return value", function()
    local b = buffer.create({})
    local result = buffer.with(b, function()
      return 42
    end)
    assert.equal(42, result)
    buffer.wipe(b)
  end)

  it("restores the previous buffer even when fn errors, and re-raises", function()
    local a = core.call("bufnr", "%")
    local b = buffer.create({})
    assert.has_error(function()
      buffer.with(b, function()
        error("boom")
      end)
    end)
    assert.equal(a, core.call("bufnr", "%")) -- still restored despite the error
    buffer.wipe(b)
  end)
end)

describe("liv.std.buffer.modifiable (L3)", function()
  it("temporarily enables 'modifiable' so a read-only buffer can be edited", function()
    local b = buffer.create({})
    buffer.set_lines(b, 1, buffer.count(b), { "locked" })
    core.call("setbufvar", b, "&modifiable", 0)

    local result = buffer.modifiable(b, function()
      buffer.set_lines(b, 1, buffer.count(b), { "edited" })
      return "ok"
    end)

    assert.equal("ok", result) -- returns fn's value
    assert.same({ "edited" }, buffer.lines(b, 1, buffer.count(b))) -- the line was written
    assert.equal(0, core.call("getbufvar", b, "&modifiable")) -- 'modifiable' restored to false
    buffer.wipe(b)
  end)

  it("restores 'modifiable' even when fn errors, and re-raises", function()
    local b = buffer.create({})
    core.call("setbufvar", b, "&modifiable", 0)
    assert.has_error(function()
      buffer.modifiable(b, function()
        error("boom")
      end)
    end)
    assert.equal(0, core.call("getbufvar", b, "&modifiable")) -- restored despite the error
    buffer.wipe(b)
  end)
end)
