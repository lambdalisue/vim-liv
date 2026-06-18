-- L1 unit test for the POSIX path flavour (spec 0006). Deterministic on any host.
local path = require("liv.lua.path.posix")

describe("path.posix.join", function()
  it("joins segments with a single separator", function()
    assert.equal("a/b/c", path.join("a", "b", "c"))
  end)

  it("collapses redundant separators between segments", function()
    assert.equal("a/b/c", path.join("a/", "/b/", "c"))
  end)

  it("ignores empty segments", function()
    assert.equal("a/b", path.join("a", "", "b"))
  end)

  it("preserves a leading absolute slash", function()
    assert.equal("/a/b", path.join("/a", "b"))
  end)
end)

describe("path.posix.dir / base", function()
  it("returns the parent directory", function()
    assert.equal("a/b", path.dir("a/b/c"))
  end)

  it("returns '.' for a bare name", function()
    assert.equal(".", path.dir("file.txt"))
  end)

  it("returns '/' for a top-level absolute path", function()
    assert.equal("/", path.dir("/file"))
  end)

  it("ignores a trailing slash", function()
    assert.equal("a", path.dir("a/b/"))
    assert.equal("b", path.base("a/b/"))
  end)

  it("returns the final component", function()
    assert.equal("c", path.base("a/b/c"))
  end)
end)

describe("path.posix backslash is an ordinary filename character", function()
  it("does not split on backslash", function()
    assert.equal(".", path.dir("a\\b"))
    assert.equal("a\\b", path.base("a\\b"))
  end)

  it("does not treat a leading backslash or drive as absolute", function()
    assert.is_false(path.is_abs("\\server\\share"))
    assert.is_false(path.is_abs("C:\\Users"))
  end)
end)

describe("path.posix.ext", function()
  it("returns the extension including the dot", function()
    assert.equal(".txt", path.ext("a/b/file.txt"))
  end)

  it("returns only the last extension", function()
    assert.equal(".gz", path.ext("archive.tar.gz"))
  end)

  it("returns empty string when there is no extension", function()
    assert.equal("", path.ext("README"))
  end)

  it("does not treat a leading-dot name as an extension", function()
    assert.equal("", path.ext(".vimrc"))
  end)
end)

describe("path.posix.normalize", function()
  it("collapses duplicate separators", function()
    assert.equal("a/b", path.normalize("a//b"))
  end)

  it("removes '.' segments", function()
    assert.equal("a/b", path.normalize("a/./b"))
  end)

  it("resolves '..' against the preceding segment", function()
    assert.equal("a/c", path.normalize("a/b/../c"))
  end)

  it("keeps leading '..' that cannot be resolved on a relative path", function()
    assert.equal("../a", path.normalize("../a"))
  end)

  it("preserves a leading absolute slash", function()
    assert.equal("/a/c", path.normalize("/a/b/../c"))
  end)

  it("normalizes to '.' for an empty relative result", function()
    assert.equal(".", path.normalize("a/.."))
  end)
end)

describe("path.posix.is_abs", function()
  it("is true for a POSIX absolute path", function()
    assert.is_true(path.is_abs("/a/b"))
  end)

  it("is false for a relative path", function()
    assert.is_false(path.is_abs("a/b"))
  end)
end)

describe("path.posix.sep", function()
  it("is '/'", function()
    assert.equal("/", path.sep)
  end)
end)
