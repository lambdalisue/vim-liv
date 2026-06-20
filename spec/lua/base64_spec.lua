-- L1 unit test for liv.lua.base64 (spec 0006). Pure, no editor. The known-answer
-- vectors are the canonical RFC 4648 §10 test set, which proves the bit packing
-- is correct across every residue (0/1/2 leftover bytes).
local base64 = require("liv.lua.base64")

describe("liv.lua.base64", function()
  describe("encode (standard RFC 4648)", function()
    it("matches the canonical RFC 4648 test vectors", function()
      assert.equal("", base64.encode(""))
      assert.equal("Zg==", base64.encode("f"))
      assert.equal("Zm8=", base64.encode("fo"))
      assert.equal("Zm9v", base64.encode("foo"))
      assert.equal("Zm9vYg==", base64.encode("foob"))
      assert.equal("Zm9vYmE=", base64.encode("fooba"))
      assert.equal("Zm9vYmFy", base64.encode("foobar"))
    end)

    it("is binary-safe with NUL and high bytes", function()
      local raw = "\0\255\1\254\128\127"
      assert.equal(raw, base64.decode(base64.encode(raw)))
    end)

    it("round-trips every byte value", function()
      local bytes = {}
      for i = 0, 255 do
        bytes[i + 1] = string.char(i)
      end
      local all = table.concat(bytes)
      assert.equal(all, base64.decode(base64.encode(all)))
    end)
  end)

  describe("decode (standard RFC 4648)", function()
    it("inverts the canonical vectors", function()
      assert.equal("", base64.decode(""))
      assert.equal("f", base64.decode("Zg=="))
      assert.equal("fo", base64.decode("Zm8="))
      assert.equal("foo", base64.decode("Zm9v"))
      assert.equal("foob", base64.decode("Zm9vYg=="))
      assert.equal("fooba", base64.decode("Zm9vYmE="))
      assert.equal("foobar", base64.decode("Zm9vYmFy"))
    end)

    it("ignores ASCII whitespace in the input", function()
      assert.equal("foobar", base64.decode("Zm9v\nYmFy\n"))
      assert.equal("foobar", base64.decode("Zm9v YmFy"))
    end)

    it("raises a prefixed error on an invalid alphabet character", function()
      local ok, err = pcall(base64.decode, "Zm9v*===")
      assert.is_false(ok)
      assert.is_true(
        tostring(err):find("liv.lua.base64", 1, true) ~= nil,
        "expected liv.lua.base64-prefixed error, got: " .. tostring(err)
      )
    end)
  end)

  describe("leaf-direct require (tree-shaking surface)", function()
    -- The family is split so an encode-only consumer never vendors the decoder
    -- and vice versa. Each side is requirable on its own through its public leaf.
    it("exposes encode / encode_url through the encode leaf alone", function()
      local encode = require("liv.lua.base64.encode")
      assert.equal("Zm9vYmFy", encode.encode("foobar"))
      assert.equal("Zg==", encode.encode("f"))
      assert.equal("Zg", encode.encode_url("f"))
      assert.equal("Pz8_", encode.encode_url("???"))
    end)

    it("exposes decode / decode_url through the decode leaf alone", function()
      local decode = require("liv.lua.base64.decode")
      assert.equal("foobar", decode.decode("Zm9vYmFy"))
      assert.equal("f", decode.decode("Zg=="))
      assert.equal("f", decode.decode_url("Zg"))
      assert.equal("\251\255", decode.decode_url("-_8"))
    end)

    it("keeps the module-prefixed error on the decode leaf", function()
      local decode = require("liv.lua.base64.decode")
      local ok, err = pcall(decode.decode, "Zm9v*===")
      assert.is_false(ok)
      assert.is_true(
        tostring(err):find("liv.lua.base64", 1, true) ~= nil,
        "expected liv.lua.base64-prefixed error, got: " .. tostring(err)
      )
    end)
  end)

  describe("URL-safe variant (encode_url / decode_url)", function()
    it("emits - and _ instead of + and / and omits padding", function()
      -- "???" (0x3F x3) encodes to "Pz8/" in standard base64 (uses /); the two
      -- bytes 0xFB,0xEF,0xFF encode to "++//" (uses both + and /). The URL-safe
      -- alphabet maps + -> - and / -> _, and emits no trailing '='.
      assert.equal("Pz8_", base64.encode_url("???"))
      assert.equal("--__", base64.encode_url("\251\239\255"))
      assert.equal("-_8", base64.encode_url("\251\255"))
      assert.equal("Zg", base64.encode_url("f"))
      assert.equal("Zm8", base64.encode_url("fo"))
      assert.equal("Zm9v", base64.encode_url("foo"))
    end)

    it("decodes both unpadded and padded URL-safe input", function()
      assert.equal("f", base64.decode_url("Zg"))
      assert.equal("f", base64.decode_url("Zg=="))
      assert.equal("fo", base64.decode_url("Zm8"))
      assert.equal("\251\255", base64.decode_url("-_8"))
      assert.equal("\251\255", base64.decode_url("-_8="))
    end)

    it("round-trips binary through the URL-safe variant", function()
      local raw = "\0\255\62\63\251\127\128"
      assert.equal(raw, base64.decode_url(base64.encode_url(raw)))
    end)
  end)
end)
