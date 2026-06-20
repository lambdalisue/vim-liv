-- L3 integration test for liv.std.hash (spec 0006), on both editors. Verifies the
-- editor's native sha256() builtin agrees with the canonical vector AND with the
-- pure liv.lua.hash implementation, so the fast (builtin) path and the portable
-- (pure) path are interchangeable.
local hash = require("liv.std.hash")
local pure = require("liv.lua.hash")

describe("liv.std.hash (L3)", function()
  it("computes sha256 via the editor builtin matching the canonical vector", function()
    assert.equal(
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      hash.sha256("")
    )
    assert.equal(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      hash.sha256("abc")
    )
  end)

  it("agrees with the pure liv.lua.hash sha256", function()
    assert.equal(pure.sha256("abc"), hash.sha256("abc"))
    assert.equal(
      pure.sha256("The quick brown fox jumps over the lazy dog"),
      hash.sha256("The quick brown fox jumps over the lazy dog")
    )
  end)

  it("exposes md5 and sha1 (delegating to the pure implementation)", function()
    assert.equal("900150983cd24fb0d6963f7d28e17f72", hash.md5("abc"))
    assert.equal("a9993e364706816aba3e25717850c26c9cd0d89d", hash.sha1("abc"))
  end)
end)
