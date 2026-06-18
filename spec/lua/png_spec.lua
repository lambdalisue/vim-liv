-- L1 unit test for liv.lua.png (spec 0006, note §19). Pure, no editor. Decodes a
-- REAL PNG produced by python (so the inflate + unfilter path is exercised against
-- an external encoder) to known pixels, and round-trips encode→decode.
local png = require("liv.lua.png")

local function readfile(p)
  local f = assert(io.open(p, "rb"))
  local d = f:read("*a")
  f:close()
  return d
end

describe("liv.lua.png", function()
  it("decodes a tiny RGBA PNG to known pixels", function()
    local img = png.decode(readfile("spec/fixtures/png/tiny.png"))
    assert.equal(3, img.width)
    assert.equal(2, img.height)
    assert.equal("rgba", img.format)
    assert.equal(readfile("spec/fixtures/png/tiny.rgba"), img.data)
  end)

  it("decodes an adaptively-filtered PNG (Sub/Up/Average/Paeth) to known pixels", function()
    -- filtered.png was written by PIL, which picks a different filter per row, so
    -- this exercises all five unfilter cases against an external encoder.
    local img = png.decode(readfile("spec/fixtures/png/filtered.png"))
    assert.equal(17, img.width)
    assert.equal(13, img.height)
    assert.equal("rgba", img.format)
    assert.equal(readfile("spec/fixtures/png/filtered.rgba"), img.data)
  end)

  it("encode then decode round-trips the pixels", function()
    local src = readfile("spec/fixtures/png/tiny.rgba")
    local encoded = png.encode({ data = src, width = 3, height = 2, format = "rgba" })
    local img = png.decode(encoded)
    assert.equal(3, img.width)
    assert.equal(2, img.height)
    assert.equal("rgba", img.format)
    assert.equal(src, img.data)
  end)

  it("raises a prefixed error on truncated input", function()
    -- Truncating a valid PNG mid-stream must raise a liv-branded error, never an
    -- unguarded "arithmetic on a nil value" from reading past the end.
    -- Lengths that cut at different stages: the IHDR length field, mid-IHDR, the
    -- compressed IDAT stream (into zlib), and just-short pixel data after inflate.
    local full = readfile("spec/fixtures/png/tiny.png")
    for _, n in ipairs({ 10, 20, 40, 50 }) do
      local ok, err = pcall(png.decode, string.sub(full, 1, n))
      assert.is_false(ok)
      assert.is_true(
        tostring(err):find("liv.lua.", 1, true) ~= nil,
        "expected liv-branded error at len " .. n .. ", got: " .. tostring(err)
      )
    end
  end)
end)
