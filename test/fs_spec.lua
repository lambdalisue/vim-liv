-- L3 integration test for liv.std.fs (spec 0006/0007). Real files on both
-- editors; the key claim is binary-safe sync read/write.
local fs = require("liv.std.fs")
local core = require("liv.core")

local dir = "/tmp/liv_fs_test"

describe("liv.std.fs (L3)", function()
  before_each(function()
    core.call("delete", dir, "rf")
    core.call("mkdir", dir, "p")
  end)

  it("write then read round-trips binary-safe bytes (NUL, newlines)", function()
    local path = dir .. "/data.bin"
    local content = "line1\nline2\000binary\255end"
    fs.write(path, content)
    assert.equal(content, fs.read(path))
  end)

  it("read/write accept an optional opts table (reserved, sync behavior kept)", function()
    local path = dir .. "/opts.txt"
    fs.write(path, "x", {})
    assert.equal("x", fs.read(path, {}))
  end)

  it("read errors (pcall-able) on a missing file", function()
    assert.has_error(function()
      fs.read(dir .. "/nope.txt")
    end)
  end)

  it("stat returns size, mtime, and type for a real file", function()
    local path = dir .. "/s.txt"
    fs.write(path, "hello")
    local st = fs.stat(path)
    assert.equal(5, st.size)
    assert.equal("file", st.type)
    assert.is_true(st.mtime > 0)
  end)

  it("stat reports a directory", function()
    assert.equal("dir", fs.stat(dir).type)
  end)

  it("stat reports a symlink as type 'link' (does not follow it)", function()
    local target = dir .. "/target.txt"
    local link = dir .. "/link.txt"
    fs.write(target, "hi")
    os.execute("ln -s " .. target .. " " .. link)
    assert.equal("link", fs.stat(link).type)
  end)

  it("stat returns nil for a nonexistent path", function()
    assert.is_nil(fs.stat(dir .. "/does-not-exist"))
  end)

  it("scandir lists the entries under a directory", function()
    fs.write(dir .. "/a.txt", "a")
    fs.write(dir .. "/b.txt", "b")
    local names = fs.scandir(dir)
    local seen = {}
    for _, n in ipairs(names) do
      seen[n] = true
    end
    assert.is_true(seen["a.txt"])
    assert.is_true(seen["b.txt"])
  end)
end)
