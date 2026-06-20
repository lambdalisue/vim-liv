# Rule: own the contract, distinct naming

liv owns its own stable, cross-editor API contract (like `@denops/std`). It does
NOT polyfill or mirror Neovim's API.

## Naming

- **Never mimic Neovim's API names or shapes**: `nvim_*`, `vim.api.*`, `extmark`,
  `vim.uv`, `vim.schedule`, `vim.keymap.set`. "Similar but different" creates
  false familiarity and silent bugs. **Different behavior → different name.**
- **Domain vocabulary is fine** (buffer, window, tabpage, option, autocmd):
  these are editor-shared concepts, not Neovim-specific coinages. Prefer the real
  domain word — `autocmd` (`:autocmd` is an Ex command on both editors) reads
  clearer than an invented synonym like `event`.
- Shape APIs from liv's own coherent model: `liv.std.<area>.<verb>`.

## Conventions (documented loudly; all APIs follow them)

- **Ranges: 1-based, inclusive** (Lua/Vim native). NOT Neovim's 0-based/exclusive.
- **Handles**: integer ids for buffer/window/tabpage; `0` or `nil` means current.
- **Positions**: `{line, col}`, 1-based.
- **Errors**: raise via `error()` (pcall-able). Async errors propagate through
  `await`.
- **Callbacks**: plain Lua functions passed directly (both editors keep them
  alive). No public `register` primitive. The only exception is Vim's
  string-only contexts (`:command`/`:autocmd`/`:map` ex-string rhs, some expr
  options), handled by an internal id→Lua dispatch inside the relevant `_vim`
  backend — not a public API.

## Capability and degradation

- Power features unavailable on Vim (treesitter, lsp, true libuv) are NOT in the
  contract. Expose `liv.std.has(feature)` so authors branch intentionally; degrade
  gracefully — never fail silently.
