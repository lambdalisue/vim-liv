# 0005 — Value marshaling (`liv.core`)

Lua has one table type for both arrays and maps; Vim/Neovim distinguish List and
Dict. `liv.core` absorbs this **bidirectionally** inside its primitives, so
`liv.std` only ever sees plain, normalized Lua values.

## Problem

- Empty `{}` is ambiguous (list or dict). Once it becomes Lua `{}`, type info is
  lost (Neovim preserves it via `vim.empty_dict()`).
- `nil` cannot live in a Lua table → need a `NIL` sentinel for `v:null`/`vim.NIL`.
- Vim converts Lua booleans to numbers in some paths → need explicit
  `v:true`/`v:false` handling.
- Integer vs Float (Vim Number/Float; Lua 5.3+ int/float; 5.1/LuaJIT double only).
- On output, Vim returns List/Dict as **userdata**; Neovim returns plain tables.

## API

```lua
liv.core.NIL              -- null sentinel (<-> v:null / vim.NIL); usable inside tables
liv.core.list(t)          -- mark t as a list (metatable tag; highest priority)
liv.core.dict(t)          -- mark t as a dict
liv.core.empty_dict()     -- = liv.core.dict({})
liv.core.is_list(t) / liv.core.is_dict(t)
```

## Classification (pure Lua, deterministic) — L1 testable

```lua
local function classify(t)
  local mt = getmetatable(t)
  if mt == LIST_MT then return "list" end   -- 1. explicit liv.core.list
  if mt == DICT_MT then return "dict" end    -- 2. explicit liv.core.dict
  if next(t) == nil then return "list" end   -- 3. EMPTY -> list (default)
  local n = 0; for _ in pairs(t) do n = n + 1 end
  if n == #t then return "list" end          -- 4. proper 1..n sequence -> list
  return "dict"                               -- 5. otherwise -> dict
end
```

| input | result | note |
| --- | --- | --- |
| `liv.core.list/dict(t)` | per tag | highest priority |
| `{}` (empty) | **list** | default; use `empty_dict()` for an empty dict |
| `{1,2,3}` | list | |
| `{a=1}` / string keys | dict | dict keys stringified |
| mixed / sparse | dict | integer keys stringified |

## Round-trip guarantee

Only empty containers need a tag (non-empty are recovered from structure).
On output, an editor empty **Dict** is returned as `liv.core.empty_dict()` (tagged)
so it round-trips as a dict.

| Lua value | → editor | → Lua (read back) |
| --- | --- | --- |
| `{}` (plain) | empty List | `{}` (list) ✓ |
| `empty_dict()` | empty Dict | `empty_dict()` ✓ |
| `{1,2}` / `{a=1}` | List / Dict | same ✓ |
| `core.NIL` | `v:null` / `vim.NIL` | `core.NIL` ✓ |

## Scalar rules

- **null**: `v:null`/`vim.NIL` ↔ `core.NIL`.
- **boolean**: Lua `true/false` → `v:true`/`v:false` (avoid Vim's bool→number);
  output → Lua boolean.
- **number**: integral (`math.type=="integer"` or `n % 1 == 0`) → Number; else
  Float.
- **string**: UTF-8 bytes; treat as code points, never byte-slice.

## Performance

Marshaling is deep/recursive. Skip it on scalar-only paths (decided at codegen
for generated wrappers); default to correctness. `classify` is a single O(n) pass.
