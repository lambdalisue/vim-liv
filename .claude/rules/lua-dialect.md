# Rule: Lua 5.1-compatible dialect

Vim may link any of Lua 5.1–5.4 or LuaJIT; Neovim is LuaJIT (5.1-compatible).
The lowest common denominator is **Lua 5.1**, so all source MUST be written in a
5.1-compatible dialect. The bundler does NOT transpile — compatibility is carried
by a bundled compat shim, not by syntax downleveling.

## Forbidden (5.2+/5.3+ only) — do not use

- `goto` / labels (5.2+)
- Integer division operator `//` and bitwise operators `& | ~ << >>` (5.3+)
  — use the compat shim's bit functions instead.
- `<close>` / `<const>` attributes (5.4)
- Relying on `math.type`, integer/float subtypes (5.3+) without a 5.1 fallback
  (use `n % 1 == 0` to detect integrality).

## Use the shim, not raw stdlib differences

- `unpack` vs `table.unpack` — use the shim alias.
- `package.loaders` vs `package.searchers` — use the shim alias.
- Removed functions (`math.pow`, `math.atan2`, …) — use the shim.

## Other

- Pure-Lua modules must not touch the editor (`vim.*`); only the compat shim.
- Comments and messages in English.
