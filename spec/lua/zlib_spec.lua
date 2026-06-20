-- L1 unit test for liv.lua.zlib (spec 0006, note §19.1). Pure, no editor. The
-- inflate oracle is a REAL zlib stream produced by python's zlib (so inflate must
-- handle dynamic-Huffman DEFLATE, not just our own output); deflate need only emit
-- a valid stream that round-trips.
local zlib = require("liv.lua.zlib")

local function readfile(p)
  local f = assert(io.open(p, "rb"))
  local d = f:read("*a")
  f:close()
  return d
end

describe("liv.lua.zlib", function()
  it("inflates a real (externally produced) zlib stream", function()
    local stream = readfile("spec/fixtures/png/stream.zlib")
    local plain = readfile("spec/fixtures/png/stream.plain")
    assert.equal(plain, zlib.inflate(stream))
  end)

  it("deflate then inflate round-trips arbitrary bytes", function()
    local data = "The quick brown fox \0\1\2 jumps over 13 lazy dogs."
    assert.equal(data, zlib.inflate(zlib.deflate(data)))
  end)

  it("round-trips empty and large data", function()
    assert.equal("", zlib.inflate(zlib.deflate("")))
    local big = string.rep("liv-", 5000)
    assert.equal(big, zlib.inflate(zlib.deflate(big)))
  end)

  it("raises a prefixed error on a truncated stored stream", function()
    -- A truncated stored (uncompressed) block reads raw bytes past the end; it
    -- must raise the module-prefixed error, not an unguarded arithmetic error.
    local full = zlib.deflate(string.rep("x", 200))
    local ok, err = pcall(zlib.inflate, string.sub(full, 1, 6))
    assert.is_false(ok)
    assert.is_true(
      tostring(err):find("liv.lua.zlib", 1, true) ~= nil,
      "expected liv.lua.zlib-prefixed error, got: " .. tostring(err)
    )
  end)
end)

-- The leaves are public so a consumer can bundle just one codec direction
-- (decompress-only / compress-only) without pulling the whole zlib family.
describe("liv.lua.zlib leaves", function()
  it("exposes inflate via the public leaf without requiring the barrel", function()
    local inflate = require("liv.lua.zlib.inflate")
    local stream = readfile("spec/fixtures/png/stream.zlib")
    local plain = readfile("spec/fixtures/png/stream.plain")
    assert.equal(plain, inflate.inflate(stream))
  end)

  it("exposes deflate via the public leaf without requiring the barrel", function()
    local deflate = require("liv.lua.zlib.deflate")
    local inflate = require("liv.lua.zlib.inflate")
    local data = "round-trip via leaves \0\1\2"
    assert.equal(data, inflate.inflate(deflate.deflate(data)))
  end)
end)
