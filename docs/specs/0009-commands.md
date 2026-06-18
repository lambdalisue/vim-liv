# 0009 — Commands & CLI

## CLI is primary; editor commands are thin wrappers

Each dev tool (`liv.bundler`, `liv.tester`, `liv.generator`) has **one canonical
entry**, a Lua `liv.<tool>.cli.main(args)`. Everything else is a thin shim over it:

- `bin/liv-<tool>` — a terminal entry (run in CI or a shell); self-locates the
  vim-liv install and calls `cli.main`.
- `:Liv*` Ex commands (registered by `plugin/liv.vim`) — parse their arguments
  and call the **same** `cli.main`. They add no logic of their own.

This keeps one implementation, makes standalone/CI use first-class, and means the
editor commands and the terminal CLI can never drift. Some inputs are only
available in one shim (e.g. `--source=rtp` needs a running editor's
`&runtimepath`, so it is meaningful from `:LivBundle` but not the standalone
binary); such cases are noted per option rather than duplicated in logic.

## Commands

### Bundler (`liv.bundler.cli`; shims `bin/liv-bundler`, `:Liv*`)

| command | role |
| --- | --- |
| `:LivBundle [module...] [--source=rtp\|git\|luarock\|path] [--from=...] [--ref=...] [--to=dir]` | Vendor module(s) + transitive deps; rewrite namespaces; write lockfile. No args = rebuild from lockfile. `:LivBundle liv.lua.async` = that subtree only (minimal, vitalizer parity). |
| `:LivUpdate [module...]` | Re-vendor to newer versions (per each module's recorded source); show **migration notices** for affected modules ([0008](0008-bundler.md)); confirm; update lockfile. |
| `:LivCheck` | Read-only: doctor (`+lua`? `git`?) + drift (vendor tree vs lockfile) + outdated report. |
| `:LivRemove module...` | Remove module(s) and now-unused dependencies; update lockfile (vitalizer's `-Module`). |

### Tester (`liv.tester.cli`; shims `bin/liv-tester`, `:LivTest`)

| entry | role |
| --- | --- |
| `bin/liv-tester` / `:LivTest` | Run the plugin's specs: `spec/` as L1 (editor-free, in-process) and `test/` as L3 (inside Vim +lua **and** Neovim, headless); aggregate results; nonzero exit on failure. No per-project runner script needed. |

### Generator (`liv.generator`; shim `bin/liv-generator`)

| entry | role |
| --- | --- |
| `bin/liv-generator` | Regenerate the typed editor-API wrappers (`liv.std.fn` builtins, `liv.std.option` options) and their LuaLS annotations from the **pinned** Vim/Neovim docs (`liv.generator.supported_versions`). Dev-time only; emits committed source, never runs at a consumer's runtime. |

## `--source` (default `rtp`)

Source is recorded **per module** in the lockfile; `--source` sets the default for
this invocation. `:LivUpdate` / `:LivCheck` re-resolve using each module's recorded
source.

- **`rtp` (default; in-editor only)** — resolve from `&runtimepath`'s `lua/` and
  vendor. Vim globs `runtimepath`; Neovim resolves natively. `liv.core`/`liv.std`
  are on `runtimepath` once `vim-liv` is installed, so `:LivBundle liv.lua.async`
  just works. If the resolved source dir is a git checkout, its sha is recorded.
- **`git`** — `--from=URL --ref=...`: fetch then vendor; pin the ref.
- **`luarock`** — third-party pure-Lua libs (optional; later).
- **`path`** — a local directory (developing an uninstalled dep).
- **Standalone CLI (no editor)** cannot use `rtp`; specify `git`/`luarock`/`path`.

## Target plugin

Inferred from the current working directory / git root; overridable with `--to=dir`
(vitalizer takes an explicit target; liv infers + allows override).
