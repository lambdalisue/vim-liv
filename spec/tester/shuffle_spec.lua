-- L1 self-test for liv.tester._shuffle — the deterministic, editor-independent
-- order randomizer used by `--seed N` (spec 0010).
--
-- It must NOT use `math.random`: that RNG differs across LuaJIT and PUC-Lua
-- 5.1–5.4, so the SAME seed would shuffle differently on Vim's Lua vs Neovim's
-- LuaJIT — defeating the whole point (reproducing a failing order). A tiny
-- self-contained LCG gives one order per seed on every host.
local shuffle = require("liv.tester._shuffle")

describe("liv.tester._shuffle.order", function()
  it("returns a permutation of the input (same elements)", function()
    local input = { "a", "b", "c", "d", "e" }
    local out = shuffle.order(input, 123)
    assert.equal(#input, #out)
    local seen = {}
    for _, v in ipairs(out) do
      seen[v] = (seen[v] or 0) + 1
    end
    for _, v in ipairs(input) do
      assert.equal(1, seen[v])
    end
  end)

  it("is deterministic: the same seed yields the same order", function()
    local input = { 1, 2, 3, 4, 5, 6, 7, 8 }
    local a = shuffle.order(input, 42)
    local b = shuffle.order(input, 42)
    assert.same(a, b)
  end)

  it("a different seed generally yields a different order", function()
    local input = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
    local a = shuffle.order(input, 1)
    local b = shuffle.order(input, 2)
    -- Not a hard guarantee for all inputs, but for 10 elements two seeds should
    -- differ; assert they are not identical sequences.
    local same = true
    for i = 1, #a do
      if a[i] ~= b[i] then
        same = false
        break
      end
    end
    assert.is_false(same)
  end)

  it("does not mutate the input list", function()
    local input = { "x", "y", "z" }
    shuffle.order(input, 7)
    assert.same({ "x", "y", "z" }, input)
  end)

  it("does not perturb the global math.random stream", function()
    math.randomseed(99)
    local before = math.random()
    math.randomseed(99)
    shuffle.order({ 1, 2, 3, 4, 5 }, 12345)
    local after = math.random()
    assert.equal(before, after)
  end)
end)
