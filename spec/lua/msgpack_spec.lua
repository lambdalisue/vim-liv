-- L1 unit test for liv.lua.msgpack (spec 0006). Pure, no editor. Pins the wire
-- format with byte-vector oracles (so a regression in the encoder is caught
-- exactly) and proves encode/decode are inverses across the type space, including
-- the list/dict/NIL shape markers shared with liv.lua.value.
local mp = require("liv.lua.msgpack")
local value = require("liv.lua.value")

-- decode just the value (drop the trailing offset)
local function rt(x)
  return (mp.decode(mp.encode(x)))
end

describe("liv.lua.msgpack encode (wire format)", function()
  local cases = {
    { 0, "\x00" },
    { 127, "\x7f" },
    { 128, "\xcc\x80" },
    { 255, "\xcc\xff" },
    { 256, "\xcd\x01\x00" },
    { 65536, "\xce\x00\x01\x00\x00" },
    { -1, "\xff" },
    { -32, "\xe0" },
    { -33, "\xd0\xdf" },
    { -128, "\xd0\x80" },
    { -129, "\xd1\xff\x7f" },
    { true, "\xc3" },
    { false, "\xc2" },
    { "", "\xa0" },
    { "a", "\xa1a" },
    { 1.5, "\xcb\x3f\xf8\x00\x00\x00\x00\x00\x00" },
  }
  for _, c in ipairs(cases) do
    it("encodes " .. tostring(c[1]), function()
      assert.equal(c[2], mp.encode(c[1]))
    end)
  end

  it("encodes the NIL sentinel as msgpack nil", function()
    assert.equal("\xc0", mp.encode(value.NIL))
  end)

  it("encodes an empty table as an array, empty_dict as a map", function()
    assert.equal("\x90", mp.encode({}))
    assert.equal("\x80", mp.encode(value.empty_dict()))
  end)

  it("encodes a small array and map", function()
    assert.equal("\x93\x01\x02\x03", mp.encode({ 1, 2, 3 }))
    assert.equal("\x81\xa1k\x01", mp.encode({ k = 1 }))
  end)
end)

describe("liv.lua.msgpack decode", function()
  it("decodes a known array", function()
    local v, nxt = mp.decode("\x93\x01\x02\x03")
    assert.same({ 1, 2, 3 }, v)
    assert.equal(5, nxt)
  end)

  it("decodes msgpack nil to the NIL sentinel", function()
    assert.equal(value.NIL, mp.decode("\xc0"))
  end)
end)

describe("liv.lua.msgpack round-trips", function()
  it("round-trips integers across all widths", function()
    local ns = { 0, 1, 127, 128, 255, 256, 65535, 65536, 4294967295, 4294967296, 1099511627776, -1, -32, -33, -128, -129, -32768, -32769, -2147483648, -2147483649, -1099511627776 }
    for _, n in ipairs(ns) do
      assert.equal(n, rt(n))
    end
  end)

  it("round-trips floats exactly (IEEE754 bit-for-bit)", function()
    local fs = { 1.5, 0.1, -0.25, math.pi, 1e300, 1e-300, -2.5, 123456.789 }
    for _, f in ipairs(fs) do
      assert.equal(f, rt(f))
    end
  end)

  it("round-trips booleans and nil", function()
    assert.equal(true, rt(true))
    assert.equal(false, rt(false))
    assert.equal(value.NIL, rt(value.NIL))
    assert.equal(value.NIL, rt(nil))
  end)

  it("round-trips strings of varied lengths", function()
    for _, len in ipairs({ 0, 1, 31, 32, 255, 256, 70000 }) do
      local s = string.rep("x", len)
      assert.equal(s, rt(s))
    end
  end)

  it("round-trips nested arrays and maps", function()
    local v = { 1, "two", { 3, 4 }, { name = "liv", nums = { 5, 6, 7 } } }
    assert.same(v, rt(v))
  end)

  it("preserves dict-ness of an empty map", function()
    local v = rt(value.empty_dict())
    assert.is_true(value.is_dict(v))
  end)
end)

describe("liv.lua.msgpack decode (truncated input)", function()
  -- Truncated input must raise the module-prefixed error like an unsupported
  -- byte does, never an unguarded "arithmetic on a nil value" stdlib error.
  local truncated = {
    { "empty", "" },
    { "uint16 missing a byte", "\xcd\x00" },
    { "uint32 missing bytes", "\xce\x00\x00" },
    { "str8 body short", "\xd9\x05ab" },
    { "array element missing", "\x91" },
    { "map value missing", "\x81\xa1k" },
    { "double short", "\xcb\x00\x00" },
  }
  for _, case in ipairs(truncated) do
    it("raises a prefixed error on " .. case[1], function()
      local ok, err = pcall(mp.decode, case[2])
      assert.is_false(ok)
      assert.is_true(
        tostring(err):find("liv.lua.msgpack", 1, true) ~= nil,
        "expected liv.lua.msgpack-prefixed error, got: " .. tostring(err)
      )
    end)
  end
end)
