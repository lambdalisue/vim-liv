# 0008 — `liv.bundler`

The build-time tool that vendors `liv.core` / `liv.std` (and other Lua deps) into
a consumer plugin. Pure Lua, editor-independent (except the `rtp` source resolver,
which reads `&runtimepath`). **Never vendored** (not in any consumer runtime
require graph). It distills the essence of vital.vim's **vitalizer**.

## Essence inherited from vitalizer (and how liv differs)

| vitalizer | liv |
| --- | --- |
| transitive closure over `_vital_depends()` | transitive closure over static `require("literal")` + dependency manifest |
| also bundles data-file deps (`files`) | also bundles non-`.lua` companions (Vim 9 `.vim`, data) via manifest |
| rewrite `__vital__` → `_{plugin}` (unique per plugin) | rewrite `liv.*` → `<plugin>.vendor.liv.*` |
| no collisions across plugins | namespace rewrite gives `package.loaded` isolation |
| version = git-hash snapshot in `.vital`; `--hash=` pin | per-module source+version in a **lockfile**; pin via git sha |
| **`Changes` shows breaking changes for installed modules only** | **migration notices** (the headline feature; see below) |
| diff update (`+Module`/`-Module`) | lockfile-driven add/update/remove |
| clean reinstall; CRLF-safe copy; completion | same |

The SID `autoloadablize` injection vitalizer needs is **not needed** — Lua has
`require`.

## Pipeline / modules

- `analyze` — parse string-literal `require`s; compute the transitive closure;
  read dependency manifests for dynamic deps and non-Lua companions.
- `rewrite` — rewrite inter-module `require` strings to the plugin-owned prefix
  (`<plugin>.vendor.liv.*`). Content-hash sub-namespace only for diamond conflicts
  (two incompatible versions of one lib in one bundle); identical hash loads once.
- `lockfile` — record, per module: source (`rtp`/`git`/`luarock`/`path`), version
  (git sha or semver), content-hash. Same lockfile + same inputs → identical
  vendor (deterministic). Drives diff add/update/remove.
- `migrate` — see below.
- `vendor` — clean the target vendor dir, then binary-safe / CRLF-normalized copy.
- `source/{rtp,git,luarock,path}` — resolvers (see [0009](0009-commands.md)).

## Dependency declaration

- Bundle-eligible modules use `require("literal")` only.
- Dynamic deps and non-Lua companions are declared in a manifest beside the
  module (modeled on `_vital_depends`'s `{modules, files}`), resolved relative to
  the module.

## Migration notices (vitalizer's headline feature)

On update (lockfile old version → new version), read the project's migration
entries (vital's `Changes` format) and show **only those affecting modules in this
bundle**, then ask for confirmation. Each entry has a version/hash, target modules
(`*` = all), and description.

```
2.0.0
    Modules: std.buffer, std.window
    lines() ranges are now 1-based inclusive (was 0-based).
1.4.0
    Modules: *
    Lua 5.1 dialect mandated; bitwise ops must go through the shim.
```

Lives in the repo root `MIGRATIONS.md`.

## Sources and luarocks

Default source is `rtp` (vitalizer model): resolve modules from `&runtimepath`'s
`lua/` and vendor them. **luarocks is NOT required for liv's own components** —
they are vendored from git/rtp. luarocks is an optional source for third-party
pure-Lua deps, and an optional later publish target for discoverability. rockspec
format may be reused as a dependency-declaration manifest without publishing.

## Output

- Default: a **multi-file vendor tree** with rewritten requires.
- Single-file amalgamation is an **optional** optimization (size/IO), not the core
  mechanism.

## MVP

Git/`rtp`-based vendoring only (vitalizer parity; no luarocks). Namespace rewrite +
lockfile + migration notices. luarocks source and amalgamation come later.
