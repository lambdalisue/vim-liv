-- L1 unit test for the Windows/UNC path flavour (spec 0006). Deterministic on
-- any host: both "/" and "\\" are separators, output uses "\\".
local path = require("liv.lua.path.unc")

describe("path.unc.sep", function()
  it("is a backslash", function()
    assert.equal("\\", path.sep)
  end)
end)

describe("path.unc.join", function()
  it("joins with a backslash separator", function()
    assert.equal("a\\b\\c", path.join("a", "b", "c"))
  end)

  it("accepts forward slashes on input and normalizes to backslash", function()
    assert.equal("a\\b\\c", path.join("a/b", "c"))
  end)

  it("preserves a leading absolute separator", function()
    assert.equal("\\a\\b", path.join("\\a", "b"))
  end)
end)

describe("path.unc.dir / base with either separator", function()
  it("splits backslash segments", function()
    assert.equal("a\\b", path.dir("a\\b\\c"))
    assert.equal("c", path.base("a\\b\\c"))
  end)

  it("splits forward-slash segments too (dir/base preserve input separators)", function()
    -- dir/base only truncate; they do not rewrite separators. Canonical
    -- SEP-normalized output is the job of join/normalize.
    assert.equal("a/b", path.dir("a/b/c"))
    assert.equal("c", path.base("a/b/c"))
  end)
end)

describe("path.unc.normalize", function()
  it("resolves '..' across mixed separators, output backslash", function()
    assert.equal("a\\c", path.normalize("a\\b\\..\\c"))
    assert.equal("a\\c", path.normalize("a/b/../c"))
  end)
end)

describe("path.unc.ext", function()
  it("takes the extension from a backslash basename", function()
    assert.equal(".txt", path.ext("a\\b\\file.txt"))
  end)
end)

describe("path.unc.is_abs", function()
  it("is true for a leading separator (either kind)", function()
    assert.is_true(path.is_abs("\\server\\share"))
    assert.is_true(path.is_abs("/a/b"))
  end)

  it("is true for a drive path", function()
    assert.is_true(path.is_abs("C:\\Users"))
    assert.is_true(path.is_abs("C:/Users"))
  end)

  it("is false for a relative path", function()
    assert.is_false(path.is_abs("a\\b"))
  end)
end)
