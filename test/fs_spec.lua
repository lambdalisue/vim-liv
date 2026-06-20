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

  describe("exists / is_dir / is_file", function()
    it("exists is true for a file and a directory, false for a missing path", function()
      fs.write(dir .. "/f.txt", "x")
      assert.is_true(fs.exists(dir .. "/f.txt"))
      assert.is_true(fs.exists(dir))
      assert.is_false(fs.exists(dir .. "/missing"))
    end)

    it("is_dir is true only for directories", function()
      fs.write(dir .. "/f.txt", "x")
      assert.is_true(fs.is_dir(dir))
      assert.is_false(fs.is_dir(dir .. "/f.txt"))
      assert.is_false(fs.is_dir(dir .. "/missing"))
    end)

    it("is_file is true only for regular files", function()
      fs.write(dir .. "/f.txt", "x")
      assert.is_true(fs.is_file(dir .. "/f.txt"))
      assert.is_false(fs.is_file(dir))
      assert.is_false(fs.is_file(dir .. "/missing"))
    end)

    it("predicates follow a symlink to a directory", function()
      local target = dir .. "/realdir"
      local link = dir .. "/linkdir"
      fs.mkdir(target)
      os.execute("ln -s " .. target .. " " .. link)
      assert.is_true(fs.is_dir(link))
      assert.is_false(fs.is_file(link))
    end)
  end)

  describe("mkdir", function()
    it("creates a single directory", function()
      fs.mkdir(dir .. "/sub")
      assert.is_true(fs.is_dir(dir .. "/sub"))
    end)

    it("creates intermediate directories with parents=true", function()
      fs.mkdir(dir .. "/a/b/c", { parents = true })
      assert.is_true(fs.is_dir(dir .. "/a/b/c"))
    end)

    it("is idempotent with parents=true when the directory already exists", function()
      fs.mkdir(dir .. "/again", { parents = true })
      -- A second call must not raise (mkdir -p semantics).
      fs.mkdir(dir .. "/again", { parents = true })
      assert.is_true(fs.is_dir(dir .. "/again"))
    end)

    it("errors when an intermediate directory is missing and parents=false", function()
      assert.has_error(function()
        fs.mkdir(dir .. "/x/y/z")
      end)
    end)

    it("errors when the directory already exists and parents=false", function()
      fs.mkdir(dir .. "/dup")
      assert.has_error(function()
        fs.mkdir(dir .. "/dup")
      end)
    end)
  end)

  describe("remove", function()
    it("removes a file", function()
      fs.write(dir .. "/r.txt", "x")
      fs.remove(dir .. "/r.txt")
      assert.is_false(fs.exists(dir .. "/r.txt"))
    end)

    it("removes a directory tree recursively", function()
      fs.mkdir(dir .. "/tree/inner", { parents = true })
      fs.write(dir .. "/tree/inner/deep.txt", "x")
      fs.remove(dir .. "/tree", { recursive = true })
      assert.is_false(fs.exists(dir .. "/tree"))
    end)

    it("errors when removing a missing path without recursive", function()
      assert.has_error(function()
        fs.remove(dir .. "/missing")
      end)
    end)

    it("is a no-op success when removing a missing path with recursive", function()
      -- rm -rf on a missing path is a no-op success; this must not raise.
      fs.remove(dir .. "/missing", { recursive = true })
      assert.is_false(fs.exists(dir .. "/missing"))
    end)
  end)

  describe("copy", function()
    it("copies a file binary-safe (NUL and high bytes preserved)", function()
      local src = dir .. "/src.bin"
      local dst = dir .. "/dst.bin"
      local content = "a\000b\255c\nd"
      fs.write(src, content)
      fs.copy(src, dst)
      assert.equal(content, fs.read(dst))
    end)

    it("copies a directory tree with recursive=true", function()
      fs.mkdir(dir .. "/from/nested", { parents = true })
      fs.write(dir .. "/from/top.txt", "top")
      fs.write(dir .. "/from/nested/leaf.txt", "leaf")
      fs.copy(dir .. "/from", dir .. "/to", { recursive = true })
      assert.equal("top", fs.read(dir .. "/to/top.txt"))
      assert.equal("leaf", fs.read(dir .. "/to/nested/leaf.txt"))
    end)
  end)

  describe("rename", function()
    it("moves a file to a new path", function()
      fs.write(dir .. "/old.txt", "data")
      fs.rename(dir .. "/old.txt", dir .. "/new.txt")
      assert.is_false(fs.exists(dir .. "/old.txt"))
      assert.equal("data", fs.read(dir .. "/new.txt"))
    end)

    it("errors when the source does not exist", function()
      assert.has_error(function()
        fs.rename(dir .. "/nope.txt", dir .. "/dest.txt")
      end)
    end)
  end)

  describe("touch", function()
    it("creates an empty file when absent", function()
      fs.touch(dir .. "/t.txt")
      assert.is_true(fs.is_file(dir .. "/t.txt"))
      assert.equal("", fs.read(dir .. "/t.txt"))
    end)

    it("leaves existing content intact", function()
      fs.write(dir .. "/keep.txt", "content")
      fs.touch(dir .. "/keep.txt")
      assert.equal("content", fs.read(dir .. "/keep.txt"))
    end)

    it("succeeds on an existing empty file", function()
      fs.write(dir .. "/empty.txt", "")
      fs.touch(dir .. "/empty.txt")
      assert.equal("", fs.read(dir .. "/empty.txt"))
    end)
  end)

  describe("tempname", function()
    it("returns a fresh unique path under the editor temp dir", function()
      local a = fs.tempname()
      local b = fs.tempname()
      assert.is_string(a)
      assert.is_true(#a > 0)
      assert.are_not.equal(a, b)
      assert.is_false(fs.exists(a))
    end)
  end)

  describe("expand", function()
    it("expands a leading ~ to the home directory", function()
      local home = os.getenv("HOME")
      assert.equal(home, fs.expand("~"))
      assert.equal(home .. "/.config", fs.expand("~/.config"))
    end)

    it("expands an environment variable reference", function()
      local home = os.getenv("HOME")
      assert.equal(home .. "/x", fs.expand("$HOME/x"))
    end)
  end)

  describe("find_upward", function()
    it("finds a marker in an ancestor directory", function()
      fs.mkdir(dir .. "/proj/src/deep", { parents = true })
      fs.write(dir .. "/proj/.marker", "")
      local found = fs.find_upward(".marker", { from = dir .. "/proj/src/deep" })
      assert.equal(dir .. "/proj/.marker", found)
    end)

    it("finds a marker in the starting directory itself", function()
      fs.mkdir(dir .. "/here", { parents = true })
      fs.write(dir .. "/here/.root", "")
      assert.equal(dir .. "/here/.root", fs.find_upward(".root", { from = dir .. "/here" }))
    end)

    it("returns nil when no ancestor holds the marker", function()
      fs.mkdir(dir .. "/lonely", { parents = true })
      assert.is_nil(fs.find_upward(".nonexistent-marker-xyz", { from = dir .. "/lonely" }))
    end)
  end)

  describe("walk", function()
    before_each(function()
      fs.mkdir(dir .. "/w/sub/deeper", { parents = true })
      fs.write(dir .. "/w/top.txt", "1")
      fs.write(dir .. "/w/.hidden", "2")
      fs.write(dir .. "/w/sub/mid.lua", "3")
      fs.write(dir .. "/w/sub/deeper/leaf.txt", "4")
    end)

    local function set(paths)
      local s = {}
      for _, p in ipairs(paths) do
        s[p] = true
      end
      return s
    end

    it("returns full paths of all entries recursively (no hidden by default)", function()
      local s = set(fs.walk(dir .. "/w"))
      assert.is_true(s[dir .. "/w/top.txt"])
      assert.is_true(s[dir .. "/w/sub"])
      assert.is_true(s[dir .. "/w/sub/mid.lua"])
      assert.is_true(s[dir .. "/w/sub/deeper/leaf.txt"])
      assert.is_nil(s[dir .. "/w/.hidden"])
    end)

    it("includes dotfiles when hidden=true", function()
      local s = set(fs.walk(dir .. "/w", { hidden = true }))
      assert.is_true(s[dir .. "/w/.hidden"])
    end)

    it("limits recursion with depth", function()
      local s = set(fs.walk(dir .. "/w", { depth = 1 }))
      assert.is_true(s[dir .. "/w/top.txt"])
      assert.is_true(s[dir .. "/w/sub"])
      assert.is_nil(s[dir .. "/w/sub/mid.lua"])
    end)

    it("filters to files with type='file'", function()
      local s = set(fs.walk(dir .. "/w", { type = "file" }))
      assert.is_true(s[dir .. "/w/top.txt"])
      assert.is_true(s[dir .. "/w/sub/mid.lua"])
      assert.is_nil(s[dir .. "/w/sub"])
      assert.is_nil(s[dir .. "/w/sub/deeper"])
    end)

    it("filters to directories with type='dir'", function()
      local s = set(fs.walk(dir .. "/w", { type = "dir" }))
      assert.is_true(s[dir .. "/w/sub"])
      assert.is_true(s[dir .. "/w/sub/deeper"])
      assert.is_nil(s[dir .. "/w/top.txt"])
    end)

    it("filters basenames by a Lua pattern", function()
      local s = set(fs.walk(dir .. "/w", { pattern = "%.lua$" }))
      assert.is_true(s[dir .. "/w/sub/mid.lua"])
      assert.is_nil(s[dir .. "/w/top.txt"])
    end)

    it("filters basenames by a predicate function", function()
      local s = set(fs.walk(dir .. "/w", {
        pattern = function(name)
          return name == "leaf.txt"
        end,
      }))
      assert.is_true(s[dir .. "/w/sub/deeper/leaf.txt"])
      assert.is_nil(s[dir .. "/w/top.txt"])
    end)
  end)
end)
