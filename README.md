# vim-liv

> **Status: design / pre-alpha.** APIs and structure are not yet stable.

**liv** is a framework for writing Lua plugins that run on **both Vim 9 (`+lua`)
and Neovim** — where installing *only the consumer plugin* is enough (all
dependencies are bundled into it).

`liv` = **L**(ua) + **I**(nterop) + **V**(im) — naming its very job: Lua ↔
Vim/Neovim *interop* (value marshaling and a single editor seam). It is also
"life" in the Nordic languages, inheriting the spirit of
[vital.vim](https://github.com/vim-jp/vital.vim)'s *vital* (life force).

## What it provides

This single repository (a Vim/Neovim plugin) hosts five namespaces:

- **`liv.core`** — the minimal, invariant *seam* over the editor (the only place
  that touches `vim.*`), plus bidirectional value marshaling. Vendored into
  consumer plugins. (A rarely-used escape hatch for authors.)
- **`liv.std`** — liv's own, stable, **editor-dependent** cross-editor API surface
  (buffer, window, event, map, process, fs, ui, float, mark, …), named by purpose.
  Vendored into consumer plugins.
- **`liv.lua`** — **editor-independent** pure-Lua modules (`liv.lua.compat`,
  `liv.lua.async`, `liv.lua.path`, …): deterministic on every host, safe for a
  library to depend on. Vendored into consumer plugins.
- **`liv.bundler`** — the build-time bundler that vendors `liv.core` / `liv.std` /
  `liv.lua` (and other Lua deps) into a consumer plugin with namespace rewriting,
  a lockfile, and migration notices. Dev-only; **never vendored**.
- **`liv.tester`** — a dependency-free, cross-editor test framework + runner
  (`bin/liv-tester`): one command runs your specs in-process (L1) and inside both
  Vim `+lua` and Neovim (L3). Dev-only; **never vendored**.

Placement rule: needs the editor → `liv.std`; pure computation → `liv.lua`; raw
editor primitive → `liv.core`. The two dev tools each expose a canonical
`liv.<tool>.cli`, with `bin/` and `:Liv*` as thin shims.

## Commands (provided to plugin authors)

- `:LivAdd [module...] [--source=rtp|git|luarock|path]` — vendor modules and
  their transitive dependencies; write the lockfile.
- `:LivUpdate [module...]` — re-vendor to newer versions and show migration
  notices for affected modules.
- `:LivCheck` — doctor + drift (vendored tree vs lockfile) + outdated report.
- `:LivRemove module...` — remove modules and now-unused dependencies.

## Design

See [`docs/specs/`](docs/specs/) for the normative specifications.

## Requirements

- Vim 9 built with `+lua`, or Neovim.
- `git` (for the bundler's `git` source and version pinning).

## License

[MIT](LICENSE)
