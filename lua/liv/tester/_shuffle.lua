-- liv.tester._shuffle — deterministic order randomization for `--seed N`.
--
-- Randomizing test order surfaces inter-test coupling (a test that only passes
-- because an earlier one left state behind). To REPRODUCE a failing order the
-- seed must yield the SAME permutation on every host — but `math.random`'s
-- algorithm differs across LuaJIT and PUC-Lua 5.1–5.4, so the same seed would
-- shuffle differently on Vim's Lua vs Neovim's LuaJIT. So this carries its own
-- tiny LCG instead of `math.random`, which also avoids perturbing the global
-- `math.random` stream a test under run might use.
--
-- Pure Lua, editor-independent, L1-testable. Used by the registry to shuffle
-- each node's children (NOT a global flatten — flattening would break before_all
-- laziness and before_each composition).

local M = {}

-- A minimal linear congruential generator (Numerical Recipes constants). 32-bit
-- state advanced with plain arithmetic + modulo (no bitwise ops, so it is Lua
-- 5.1-compatible and identical on every Lua variant). Returns a stateful
-- `next_int(n)` yielding an integer in [1, n].
---@param seed integer
---@return fun(n: integer): integer
local function lcg(seed)
  local MOD = 2 ^ 32
  -- Fold the seed into range and avoid a zero state (which an LCG cannot leave).
  local state = (math.floor(seed or 0) % MOD + MOD) % MOD
  if state == 0 then
    state = 1
  end
  return function(n)
    state = (1664525 * state + 1013904223) % MOD
    -- Map the 32-bit state to [1, n] by scaling, not modulo, so low bits (the
    -- weakest in an LCG) do not dominate the choice.
    return math.floor(state / MOD * n) + 1
  end
end

-- Return a NEW list that is a deterministic permutation of `input` for `seed`,
-- using a Fisher–Yates shuffle driven by the seeded LCG. `input` is not mutated.
---@generic T
---@param input T[]
---@param seed integer
---@return T[]
function M.order(input, seed)
  local out = {}
  for i = 1, #input do
    out[i] = input[i]
  end
  local rand = lcg(seed)
  for i = #out, 2, -1 do
    local j = rand(i)
    out[i], out[j] = out[j], out[i]
  end
  return out
end

return M
