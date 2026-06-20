-- L1 unit test for liv.lua.hash (spec 0006). Pure, no editor. The digests are
-- verified against the canonical published test vectors (RFC 1321 for MD5,
-- FIPS 180 / RFC 3174 for SHA-1, FIPS 180-4 for SHA-256, RFC 4231-style for
-- HMAC-SHA256) — the only reliable way to prove the 32-bit bit math is correct.
local hash = require("liv.lua.hash")

describe("liv.lua.hash", function()
  describe("md5", function()
    it("matches the canonical MD5 vectors", function()
      assert.equal("d41d8cd98f00b204e9800998ecf8427e", hash.md5(""))
      assert.equal("900150983cd24fb0d6963f7d28e17f72", hash.md5("abc"))
      assert.equal(
        "9e107d9d372bb6826bd81d3542a419d6",
        hash.md5("The quick brown fox jumps over the lazy dog")
      )
    end)

    it("hashes input longer than one 64-byte block", function()
      -- 80 bytes forces a second block plus length padding past the boundary.
      local long = string.rep("a", 80)
      assert.equal("b15af9cdabbaea0516866a33d8fd0f98", hash.md5(long))
    end)
  end)

  describe("sha1", function()
    it("matches the canonical SHA-1 vectors", function()
      assert.equal("da39a3ee5e6b4b0d3255bfef95601890afd80709", hash.sha1(""))
      assert.equal("a9993e364706816aba3e25717850c26c9cd0d89d", hash.sha1("abc"))
      assert.equal(
        "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12",
        hash.sha1("The quick brown fox jumps over the lazy dog")
      )
    end)
  end)

  describe("sha256", function()
    it("matches the canonical SHA-256 vectors", function()
      assert.equal(
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        hash.sha256("")
      )
      assert.equal(
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        hash.sha256("abc")
      )
      assert.equal(
        "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
        hash.sha256("The quick brown fox jumps over the lazy dog")
      )
    end)
  end)

  describe("hmac", function()
    it("matches the canonical HMAC-SHA256 vector", function()
      assert.equal(
        "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
        hash.hmac("sha256", "key", "The quick brown fox jumps over the lazy dog")
      )
    end)

    it("hashes a key longer than the block size (key gets pre-hashed)", function()
      -- RFC 4231 test case 2-style: a long key must be reduced via the hash.
      local long_key = string.rep("k", 100)
      assert.equal(
        "09380ee4b802da2363bc96e8e0d133ba275458ea8ddbc564f986fc12b31f8cb1",
        hash.hmac("sha256", long_key, "data")
      )
    end)

    it("composes over md5 and sha1 too", function()
      assert.equal(
        "80070713463e7749b90c2dc24911e275",
        hash.hmac("md5", "key", "The quick brown fox jumps over the lazy dog")
      )
      assert.equal(
        "de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9",
        hash.hmac("sha1", "key", "The quick brown fox jumps over the lazy dog")
      )
    end)
  end)
end)
