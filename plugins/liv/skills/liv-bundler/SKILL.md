---
name: liv-bundler
description: How to vendor liv (and other pure-Lua deps) into a consumer plugin with liv.bundler, so end users install only the plugin. Use when bundling/vendoring liv into a plugin, running :LivAdd/:LivUpdate/:LivCheck/:LivRemove or bin/liv-bundler, choosing a source resolver (rtp/git/path/luarock), understanding the lockfile/tree-shaking/migration-notices, or declaring dynamic deps and .vim companions in a manifest.
---

# Bundling with liv.bundler

`liv.bundler` is the build-time tool that vendors `liv.core` / `liv.std` (and
other pure-Lua deps) **into** a consumer plugin, so an end user installs only that
plugin — no `liv`, no extra runtime. It is pure Lua, editor-independent (except
the `rtp` resolver, which reads `&runtimepath`), and is a **dev tool: never
vendored** into a consumer's runtime require graph. It distills vital.vim's
*vitalizer*.

## One CLI, thin shims

Canonical entry `liv.bundler.cli.main(args)`. Two shims call the SAME entry:

- `bin/liv-bundler` — terminal/CI; self-locates the vim-liv install.
- `:Liv*` Ex commands (from `plugin/liv.vim`) — parse args, call `cli.main`. No
  logic of their own, so editor and CLI never drift.

The target plugin is inferred from the cwd / git root; override with `--to=dir`.
The `--plugin=name` sets the vendor namespace.

## Commands

| command | role |
| --- | --- |
| `:LivAdd <module>... [--source=...] [--from=URL] [--ref=...] [--to=dir] --plugin=name` | Add module(s) — the **union** with existing lockfile roots — plus transitive deps; rewrite namespaces; vendor `.vim` companions; write the lockfile. `:LivAdd liv.lua.async` adds just that subtree. |
| `:LivUpdate [module...]` | Re-vendor to current source (**no args = re-vendor ALL roots**); show **migration notices** for affected modules; update the lockfile. |
| `:LivCheck` | Read-only: report drift (source content vs lockfile hash) and modules missing from the vendor tree. |
| `:LivRemove <module>...` | Remove module(s) and now-unused deps (re-vendor remaining roots); update the lockfile. |

Add/Update/Remove complete their module arguments from `liv.bundler.list` (bundle-
able modules on `&runtimepath`, tagged bundled / not-yet-bundled).

## Pipeline (what happens inside)

- **analyze** — parse string-literal `require`s, compute the transitive closure,
  read dependency manifests for dynamic deps and non-`.lua` companions.
- **rewrite** — rewrite inter-module require strings to the plugin-owned prefix
  `<plugin>.vendor.liv.*` (gives `package.loaded` isolation). A content-hash
  sub-namespace is added only for diamond conflicts (two incompatible versions in
  one bundle); identical hash loads once.
- **lockfile** — record per module: source, version (git sha / semver),
  content-hash. Same lockfile + same inputs → identical vendor (deterministic).
  Drives diff add/update/remove.
- **vendor** — clean the target vendor dir, then binary-safe / CRLF-normalized copy.
- **migrate** — on update, show only the migration notices affecting modules in
  *this* bundle, then confirm.

Output is a **multi-file vendor tree** with rewritten requires; single-file
amalgamation is an optional later optimization.

## `--source` (default `rtp`)

Recorded **per module** in the lockfile; `--source` sets this invocation's default.
`:LivUpdate`/`:LivCheck` re-resolve using each module's recorded source.

- **`rtp`** (default; **in-editor only**) — resolve from `&runtimepath`'s `lua/`.
  `liv.core`/`liv.std` are on runtimepath once vim-liv is installed, so
  `:LivAdd liv.lua.async` just works. A git checkout's sha is recorded.
- **`git`** — `--from=URL --ref=...`: fetch then vendor; pin the ref.
- **`path`** — a local directory (developing an uninstalled dep).
- **`luarock`** — optional, third-party pure-Lua libs (later).
- The **standalone CLI** (no editor) cannot use `rtp` — pass `git`/`path`/`luarock`.

## Declaring deps the analyzer can't see

- Bundle-eligible modules use `require("literal")` ONLY (the analyzer is static).
- Dynamic deps and non-Lua companions (Vim 9 `.vim`, data files) go in a
  **manifest** beside the module (modeled on vital's `{modules, files}`), resolved
  relative to the module.

## Migration notices

Live in the repo root `MIGRATIONS.md`. Each entry: a version/hash, target modules
(`*` = all), and a description. On update, the bundler shows only those touching
modules in the current bundle and asks to confirm.

## Constraints to respect

- Native (C) modules are **out of scope** — pure Lua only.
- The bundler must **never be reachable** from a consumer plugin's runtime require
  graph (its static analysis would otherwise pull it in). It runs only via the
  `:Liv*` commands / standalone CLI.

## Deeper reference

vim-liv repo specs: `.claude/specs/0008-bundler.md`, `0009-commands.md`. Related
skill: `liv-plugin-authoring`.
