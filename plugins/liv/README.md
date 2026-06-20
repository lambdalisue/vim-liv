# liv — Claude Code plugin

Skills for writing **liv** plugins: a single Lua source that runs on both
Vim 9 (`+lua`) and Neovim, where end users install only your plugin (every
dependency is vendored in).

## Skills

| skill | use it when |
| --- | --- |
| `liv-plugin-authoring` | writing/reviewing liv code: namespace placement, own-the-contract naming, 1-based ranges, Lua 5.1 dialect, string-literal `require`, barrel/leaf splits |
| `liv-library-api` | calling or looking up a liv API: `liv.core`, the `liv.std.*` editor-dependent modules, the `liv.lua.*` pure modules, capability/degradation via `has` |
| `liv-bundler` | vendoring liv into a plugin: `:LivAdd/:LivUpdate/:LivCheck/:LivRemove`, `bin/liv-bundler`, source resolvers, lockfile, migration notices |
| `liv-tester` | writing/running cross-editor tests: L1 (`spec/`) vs L3 (`test/`), `describe`/`it`/`assert`, selectors, reporters, `bin/liv-tester` flags |

Each skill is knowledge guidance that auto-triggers from its description; deeper
detail lives in the vim-liv repo's normative specs under `.claude/specs/`.

## Install

```
/plugin marketplace add lambdalisue/vim-liv
/plugin install liv@vim-liv
```
