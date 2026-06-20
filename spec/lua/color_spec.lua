-- L1 unit test for liv.lua.color. Pure, editor-independent. Pins color
-- parsing/formatting, the RGB<->HSL conversion, the truecolor->xterm-256
-- downgrade, and RGB-space distance. liv.std.highlight defines colors but owns
-- no color MATH; this module is the math an author composes (e.g. lighten a
-- group's fg, or quantize a truecolor value for a 256-color terminal).
--
-- Color representation is a keyed table { r=, g=, b= } with channels 0-255,
-- matching the keyed-table house style and letting parse -> to_hex round-trip.
local color = require("liv.lua.color")
local color_rgb = require("liv.lua.color.rgb")
local color_hsl = require("liv.lua.color.hsl")
local color_xterm256 = require("liv.lua.color.xterm256")

describe("liv.lua.color.parse", function()
  it("parses a full '#rrggbb' string into channels", function()
    assert.same({ r = 255, g = 0, b = 0 }, color.parse("#ff0000"))
  end)

  it("parses a short '#rgb' string by doubling each nibble", function()
    assert.same({ r = 255, g = 0, b = 0 }, color.parse("#f00"))
  end)

  it("parses a mixed short form", function()
    -- #abc -> #aabbcc
    assert.same({ r = 0xaa, g = 0xbb, b = 0xcc }, color.parse("#abc"))
  end)

  it("parses an uppercase hex string", function()
    assert.same({ r = 255, g = 136, b = 0 }, color.parse("#FF8800"))
  end)

  it("parses a 0xRRGGBB integer", function()
    assert.same({ r = 255, g = 136, b = 0 }, color.parse(0xff8800))
  end)

  it("parses integer zero as black", function()
    assert.same({ r = 0, g = 0, b = 0 }, color.parse(0))
  end)

  it("errors on an unparseable string", function()
    assert.has_error(function()
      color.parse("not a color")
    end)
  end)

  it("errors on a malformed hex length", function()
    assert.has_error(function()
      color.parse("#ff00")
    end)
  end)

  it("errors on a non-hex digit", function()
    assert.has_error(function()
      color.parse("#gggggg")
    end)
  end)

  it("errors on an out-of-range integer", function()
    assert.has_error(function()
      color.parse(0x1000000) -- > 0xffffff
    end)
  end)

  it("errors on a negative integer", function()
    assert.has_error(function()
      color.parse(-1)
    end)
  end)

  it("errors on a non-integer number", function()
    assert.has_error(function()
      color.parse(1.5)
    end)
  end)
end)

describe("liv.lua.color.rgb", function()
  it("builds a color table from channels", function()
    assert.same({ r = 255, g = 136, b = 0 }, color.rgb(255, 136, 0))
  end)

  it("rounds fractional channels to the nearest integer", function()
    assert.same({ r = 128, g = 0, b = 255 }, color.rgb(127.6, 0.4, 255))
  end)

  it("clamps channels above 255 and below 0", function()
    assert.same({ r = 255, g = 0, b = 255 }, color.rgb(300, -10, 255))
  end)
end)

describe("liv.lua.color.hsl", function()
  it("converts pure red (h=0, s=1, l=0.5)", function()
    assert.same({ r = 255, g = 0, b = 0 }, color.hsl(0, 1, 0.5))
  end)

  it("converts pure green (h=120, s=1, l=0.5)", function()
    assert.same({ r = 0, g = 255, b = 0 }, color.hsl(120, 1, 0.5))
  end)

  it("converts pure blue (h=240, s=1, l=0.5)", function()
    assert.same({ r = 0, g = 0, b = 255 }, color.hsl(240, 1, 0.5))
  end)

  it("converts a desaturated mid lightness to mid gray (#808080)", function()
    assert.same({ r = 128, g = 128, b = 128 }, color.hsl(0, 0, 0.5))
  end)

  it("converts l=0 to black regardless of hue/saturation", function()
    assert.same({ r = 0, g = 0, b = 0 }, color.hsl(200, 1, 0))
  end)

  it("converts l=1 to white regardless of hue/saturation", function()
    assert.same({ r = 255, g = 255, b = 255 }, color.hsl(200, 1, 1))
  end)
end)

describe("liv.lua.color.to_hex", function()
  it("formats channels as a lowercase '#rrggbb' string", function()
    assert.equal("#ff8800", color.to_hex({ r = 255, g = 136, b = 0 }))
  end)

  it("zero-pads single-digit channels", function()
    assert.equal("#000102", color.to_hex({ r = 0, g = 1, b = 2 }))
  end)

  it("round-trips parse then to_hex", function()
    assert.equal("#abcdef", color.to_hex(color.parse("#abcdef")))
  end)
end)

describe("liv.lua.color.to_rgb", function()
  it("returns the channels as a tuple", function()
    local r, g, b = color.to_rgb({ r = 255, g = 136, b = 0 })
    assert.equal(255, r)
    assert.equal(136, g)
    assert.equal(0, b)
  end)
end)

describe("liv.lua.color.to_hsl", function()
  it("converts pure red to (0, 1, 0.5)", function()
    local h, s, l = color.to_hsl({ r = 255, g = 0, b = 0 })
    assert.equal(0, h)
    assert.equal(1, s)
    assert.equal(0.5, l)
  end)

  it("reports a gray as zero saturation", function()
    local _, s = color.to_hsl({ r = 128, g = 128, b = 128 })
    assert.equal(0, s)
  end)

  it("round-trips hsl -> rgb -> hsl within rounding tolerance", function()
    -- A non-primary hue exercises the conversion both ways. The RGB step
    -- quantizes to 0-255, so allow a small lightness/hue drift.
    local c = color.hsl(210, 0.5, 0.6)
    local h, s, l = color.to_hsl(c)
    assert.is_true(math.abs(h - 210) < 2)
    assert.is_true(math.abs(s - 0.5) < 0.02)
    assert.is_true(math.abs(l - 0.6) < 0.01)
  end)
end)

describe("liv.lua.color.to_xterm256", function()
  it("maps pure black to the cube origin (16), not system color 0", function()
    assert.equal(16, color.to_xterm256({ r = 0, g = 0, b = 0 }))
  end)

  it("maps pure white to the cube corner (231), not system color 15", function()
    assert.equal(231, color.to_xterm256({ r = 255, g = 255, b = 255 }))
  end)

  it("maps pure red to 196, not system color 9", function()
    assert.equal(196, color.to_xterm256({ r = 255, g = 0, b = 0 }))
  end)

  it("maps pure green to 46", function()
    assert.equal(46, color.to_xterm256({ r = 0, g = 255, b = 0 }))
  end)

  it("maps pure blue to 21", function()
    assert.equal(21, color.to_xterm256({ r = 0, g = 0, b = 255 }))
  end)

  it("maps a neutral mid gray into the grayscale ramp (232-255)", function()
    local idx = color.to_xterm256({ r = 128, g = 128, b = 128 })
    assert.is_true(idx >= 232 and idx <= 255)
  end)

  it("accepts a parseable color input directly", function()
    assert.equal(196, color.to_xterm256("#ff0000"))
  end)
end)

describe("liv.lua.color.distance", function()
  it("is zero for identical colors", function()
    assert.equal(0, color.distance({ r = 255, g = 0, b = 0 }, { r = 255, g = 0, b = 0 }))
  end)

  it("is the euclidean RGB distance", function()
    -- (3,4,0) -> 5
    local d = color.distance({ r = 0, g = 0, b = 0 }, { r = 3, g = 4, b = 0 })
    assert.equal(5, d)
  end)

  it("is symmetric", function()
    local a = { r = 10, g = 20, b = 30 }
    local b = { r = 200, g = 100, b = 50 }
    assert.equal(color.distance(a, b), color.distance(b, a))
  end)
end)

describe("liv.lua.color.lighten / darken", function()
  it("lighten increases lightness", function()
    local base = color.hsl(200, 0.5, 0.4)
    local _, _, l0 = color.to_hsl(base)
    local _, _, l1 = color.to_hsl(color.lighten(base, 0.2))
    assert.is_true(l1 > l0)
  end)

  it("darken decreases lightness", function()
    local base = color.hsl(200, 0.5, 0.6)
    local _, _, l0 = color.to_hsl(base)
    local _, _, l1 = color.to_hsl(color.darken(base, 0.2))
    assert.is_true(l1 < l0)
  end)

  it("lighten clamps at white", function()
    local _, _, l = color.to_hsl(color.lighten(color.hsl(200, 0.5, 0.9), 0.5))
    assert.is_true(l <= 1.0)
  end)

  it("darken clamps at black", function()
    local _, _, l = color.to_hsl(color.darken(color.hsl(200, 0.5, 0.1), 0.5))
    assert.is_true(l >= 0.0)
  end)
end)

-- Leaf-direct requires: the barrel keeps the flat API, but a consumer may bundle
-- just one concern by requiring its leaf directly. Exercise each leaf's surface
-- through its own module so the split (not only the barrel) is pinned.
describe("liv.lua.color leaves (direct require)", function()
  it("rgb leaf owns the representation verbs", function()
    assert.same({ r = 255, g = 0, b = 0 }, color_rgb.parse("#ff0000"))
    assert.same({ r = 255, g = 136, b = 0 }, color_rgb.rgb(255, 136, 0))
    assert.equal("#ff8800", color_rgb.to_hex({ r = 255, g = 136, b = 0 }))
    local r, g, b = color_rgb.to_rgb({ r = 1, g = 2, b = 3 })
    assert.same({ 1, 2, 3 }, { r, g, b })
  end)

  it("hsl leaf owns the HSL conversions and lighten/darken", function()
    assert.same({ r = 255, g = 0, b = 0 }, color_hsl.hsl(0, 1, 0.5))
    local h, s, l = color_hsl.to_hsl({ r = 255, g = 0, b = 0 })
    assert.same({ 0, 1, 0.5 }, { h, s, l })
    local _, _, ll = color_hsl.to_hsl(color_hsl.lighten(color_hsl.hsl(200, 0.5, 0.4), 0.2))
    assert.is_true(ll > 0.4)
  end)

  it("xterm256 leaf owns quantization and distance, coercing via the rgb leaf", function()
    assert.equal(196, color_xterm256.to_xterm256({ r = 255, g = 0, b = 0 }))
    -- a parseable input is coerced through the rgb leaf's parse
    assert.equal(196, color_xterm256.to_xterm256("#ff0000"))
    assert.equal(5, color_xterm256.distance({ r = 0, g = 0, b = 0 }, { r = 3, g = 4, b = 0 }))
  end)
end)
