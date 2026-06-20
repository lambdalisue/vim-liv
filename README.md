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
  (buffer, window, autocmd, mapping, process, fs, ui, popup, mark, bufname, …), named by purpose.
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

## Claude Code skills (plugin marketplace)

This repository doubles as a [Claude Code](https://claude.com/claude-code)
**plugin marketplace**: a `liv` plugin bundling four skills that teach Claude how
to author, test, and bundle liv plugins.

| skill | use it when |
| --- | --- |
| `liv-plugin-authoring` | writing/reviewing liv code: namespace placement, own-the-contract naming, 1-based ranges, the Lua 5.1 dialect, string-literal `require`, barrel/leaf splits |
| `liv-library-api` | calling or looking up a liv API: `liv.core`, the `liv.std.*` editor-dependent modules, the `liv.lua.*` pure modules, capability/degradation via `has` |
| `liv-bundler` | vendoring liv into a plugin: `:LivAdd`/`:LivUpdate`/`:LivCheck`/`:LivRemove`, `bin/liv-bundler`, source resolvers, lockfile, migration notices |
| `liv-tester` | writing/running cross-editor tests: L1 (`spec/`) vs L3 (`test/`), `describe`/`it`/`assert`, selectors, reporters, `bin/liv-tester` flags |

Each skill auto-triggers from its description; deeper detail lives in
[`.claude/specs/`](.claude/specs/).

Install from within Claude Code:

```
/plugin marketplace add lambdalisue/vim-liv
/plugin install liv@vim-liv
```

The marketplace manifest is [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json);
the plugin and its skills live under [`plugins/liv/`](plugins/liv/).

## Design

See [`.claude/specs/`](.claude/specs/) for the normative specifications.

## Requirements

- Vim 9 built with `+lua`, or Neovim.
- `git` (for the bundler's `git` source and version pinning).

## License

[MIT](LICENSE)
