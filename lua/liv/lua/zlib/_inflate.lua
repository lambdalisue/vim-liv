-- liv.lua.zlib inflater: a zlib stream (RFC 1950) -> the decompressed bytes.
-- Pure and 5.1-compatible. The DEFLATE body (RFC 1951) is decoded with the
-- canonical algorithm from zlib's `puff.c`: an LSB-first bit reader, canonical
-- Huffman code construction from per-symbol code lengths, and a length/distance
-- back-reference copy. All three block types are handled (stored, fixed-Huffman,
-- dynamic-Huffman); the adler32 trailer is not verified.
local byte = string.byte
local char = string.char
local concat = table.concat
local floor = math.floor

-- Base lengths and extra bits for the literal/length alphabet symbols 257..285.
local LEN_BASE = {
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  13,
  15,
  17,
  19,
  23,
  27,
  31,
  35,
  43,
  51,
  59,
  67,
  83,
  99,
  115,
  131,
  163,
  195,
  227,
  258,
}
local LEN_EXTRA = {
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  1,
  1,
  1,
  1,
  2,
  2,
  2,
  2,
  3,
  3,
  3,
  3,
  4,
  4,
  4,
  4,
  5,
  5,
  5,
  5,
  0,
}

-- Base distances and extra bits for the distance alphabet symbols 0..29.
local DIST_BASE = {
  1,
  2,
  3,
  4,
  5,
  7,
  9,
  13,
  17,
  25,
  33,
  49,
  65,
  97,
  129,
  193,
  257,
  385,
  513,
  769,
  1025,
  1537,
  2049,
  3073,
  4097,
  6145,
  8193,
  12289,
  16385,
  24577,
}
local DIST_EXTRA = {
  0,
  0,
  0,
  0,
  1,
  1,
  2,
  2,
  3,
  3,
  4,
  4,
  5,
  5,
  6,
  6,
  7,
  7,
  8,
  8,
  9,
  9,
  10,
  10,
  11,
  11,
  12,
  12,
  13,
  13,
}

-- Order in which the dynamic block stores the code-length code lengths.
local CL_ORDER = {
  16,
  17,
  18,
  0,
  8,
  7,
  9,
  6,
  10,
  5,
  11,
  4,
  12,
  3,
  13,
  2,
  14,
  1,
  15,
}

-- A bit reader over `s`. Bits are consumed LSB-first within each byte, the
-- order DEFLATE uses for both Huffman codes and the small fixed-width integers.
local function new_reader(s)
  return { s = s, pos = 1, bitbuf = 0, bitcnt = 0 }
end

-- Pull one bit (the next least-significant unread bit) from the stream.
local function get_bit(r)
  if r.bitcnt == 0 then
    r.bitbuf = byte(r.s, r.pos) or 0
    r.pos = r.pos + 1
    r.bitcnt = 8
  end
  local bit = r.bitbuf % 2
  r.bitbuf = floor(r.bitbuf / 2)
  r.bitcnt = r.bitcnt - 1
  return bit
end

-- Pull `n` bits as an unsigned integer, least-significant bit first.
local function get_bits(r, n)
  local v, mul = 0, 1
  for _ = 1, n do
    v = v + get_bit(r) * mul
    mul = mul * 2
  end
  return v
end

-- Build a canonical Huffman decoder from per-symbol code lengths (0 = unused).
-- Mirrors puff.c: `count[len]` symbol counts plus `symbol[]` ordered by length
-- then symbol value, consumed by `decode` walking bit-by-bit.
local function build_huffman(lengths, n)
  local count = {}
  for len = 0, 15 do
    count[len] = 0
  end
  for i = 1, n do
    count[lengths[i]] = count[lengths[i]] + 1
  end
  local offsets = {}
  offsets[1] = 0
  for len = 1, 15 do
    offsets[len + 1] = offsets[len] + count[len]
  end
  local symbols = {}
  for i = 1, n do
    local len = lengths[i]
    if len ~= 0 then
      symbols[offsets[len] + 1] = i - 1
      offsets[len] = offsets[len] + 1
    end
  end
  return { count = count, symbols = symbols }
end

-- Decode one symbol by accumulating bits MSB-first and comparing against the
-- canonical first-code-per-length, exactly as puff.c's decode() does.
local function decode_symbol(r, h)
  local count = h.count
  local code, first, index = 0, 0, 0
  for len = 1, 15 do
    code = code + get_bit(r)
    local c = count[len]
    if code - c < first then
      return h.symbols[index + (code - first) + 1]
    end
    index = index + c
    first = (first + c) * 2
    code = code * 2
  end
  error("liv.lua.zlib: invalid Huffman code")
end

-- Inflate one length/distance-coded block into `out` using the two trees.
local function inflate_block(r, out, lit_tree, dist_tree)
  while true do
    local sym = decode_symbol(r, lit_tree)
    if sym == 256 then
      return
    elseif sym < 256 then
      out[#out + 1] = char(sym)
    else
      local li = sym - 256
      local length = LEN_BASE[li] + get_bits(r, LEN_EXTRA[li])
      local dsym = decode_symbol(r, dist_tree)
      local dist = DIST_BASE[dsym + 1] + get_bits(r, DIST_EXTRA[dsym + 1])
      -- Copy byte-by-byte: overlapping copies (dist < length) repeat bytes.
      local start = #out - dist
      for k = 1, length do
        out[#out + 1] = out[start + k]
      end
    end
  end
end

-- Decode a stored (uncompressed) block: byte-align, then copy LEN raw bytes.
local function inflate_stored(r, out)
  r.bitbuf = 0
  r.bitcnt = 0
  -- Unlike get_bit (which tolerates the end with `or 0`), a stored block reads
  -- raw bytes; guard them so truncated input raises the branded error instead of
  -- an unguarded "arithmetic on a nil value".
  local lo, hi = byte(r.s, r.pos), byte(r.s, r.pos + 1)
  if not lo or not hi then
    error("liv.lua.zlib: truncated stored block header")
  end
  local len = lo + hi * 256
  r.pos = r.pos + 4 -- skip LEN (2) and its one's-complement NLEN (2)
  for _ = 1, len do
    local b = byte(r.s, r.pos)
    if not b then
      error("liv.lua.zlib: truncated stored block data")
    end
    out[#out + 1] = char(b)
    r.pos = r.pos + 1
  end
end

-- The fixed Huffman trees are constant; build them lazily once.
local fixed_lit, fixed_dist
local function fixed_trees()
  if not fixed_lit then
    local lit = {}
    for i = 1, 144 do
      lit[i] = 8
    end
    for i = 145, 256 do
      lit[i] = 9
    end
    for i = 257, 280 do
      lit[i] = 7
    end
    for i = 281, 288 do
      lit[i] = 8
    end
    local dist = {}
    for i = 1, 30 do
      dist[i] = 5
    end
    fixed_lit = build_huffman(lit, 288)
    fixed_dist = build_huffman(dist, 30)
  end
  return fixed_lit, fixed_dist
end

-- Read a dynamic block's header, build its two trees, and inflate its body.
local function inflate_dynamic(r, out)
  local hlit = get_bits(r, 5) + 257
  local hdist = get_bits(r, 5) + 1
  local hclen = get_bits(r, 4) + 4

  local cl_lengths = {}
  for i = 1, 19 do
    cl_lengths[i] = 0
  end
  for i = 1, hclen do
    cl_lengths[CL_ORDER[i] + 1] = get_bits(r, 3)
  end
  local cl_tree = build_huffman(cl_lengths, 19)

  -- Decode hlit + hdist code lengths using the code-length code.
  local lengths = {}
  local i = 1
  local total = hlit + hdist
  while i <= total do
    local sym = decode_symbol(r, cl_tree)
    if sym < 16 then
      lengths[i] = sym
      i = i + 1
    elseif sym == 16 then
      local prev = lengths[i - 1]
      local rep = get_bits(r, 2) + 3
      for _ = 1, rep do
        lengths[i] = prev
        i = i + 1
      end
    elseif sym == 17 then
      local rep = get_bits(r, 3) + 3
      for _ = 1, rep do
        lengths[i] = 0
        i = i + 1
      end
    else -- sym == 18
      local rep = get_bits(r, 7) + 11
      for _ = 1, rep do
        lengths[i] = 0
        i = i + 1
      end
    end
  end

  local lit_lengths = {}
  for k = 1, hlit do
    lit_lengths[k] = lengths[k]
  end
  local dist_lengths = {}
  for k = 1, hdist do
    dist_lengths[k] = lengths[hlit + k]
  end

  local lit_tree = build_huffman(lit_lengths, hlit)
  local dist_tree = build_huffman(dist_lengths, hdist)
  inflate_block(r, out, lit_tree, dist_tree)
end

-- Inflate a zlib stream (RFC 1950) into the original bytes.
---@param s string a complete zlib stream
---@return string plain the decompressed bytes
local function inflate(s)
  -- Skip the 2-byte zlib header (CMF, FLG); ignore the adler32 trailer.
  local r = new_reader(s)
  r.pos = 3
  local out = {}
  repeat
    local bfinal = get_bit(r)
    local btype = get_bits(r, 2)
    if btype == 0 then
      inflate_stored(r, out)
    elseif btype == 1 then
      inflate_block(r, out, fixed_trees())
    elseif btype == 2 then
      inflate_dynamic(r, out)
    else
      error("liv.lua.zlib: invalid DEFLATE block type")
    end
  until bfinal == 1
  return concat(out)
end

return { inflate = inflate }
