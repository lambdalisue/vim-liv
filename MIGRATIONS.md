# Migrations

Breaking-change notices, consumed by `:LivUpdate` to warn about changes affecting
the modules a plugin actually bundles (see `.claude/specs/0008-bundler.md`).

Format: one entry per version, newest first.

```
<version-or-hash>
    Modules: <comma-separated module list, or * for all>
    <one or more description lines>
```

```
Unreleased
    Modules: liv.std.variable, liv.std.function, liv.std.mapping, liv.std.popup, liv.std.bufname, liv.std.process, liv.std.mark, liv.has
    BREAKING: std modules renamed to align with denops/std vocabulary. API
    signatures are unchanged — only the module path/name moved. Update requires:
      liv.std.var   -> liv.std.variable
      liv.std.map   -> liv.std.mapping
      liv.std.float -> liv.std.popup
      liv.std.fn    -> liv.std.function
    The liv.has capability keys for popup windows were renamed to match:
      has("float")        -> has("popup")
      has("float.border") -> has("popup.border")
    ADD: new pure module liv.std.bufname — buffer-name codec mirroring
    denops/std bufname. format({scheme,expr,params?,fragment?}) -> string and
    parse(string) -> bufname over the wire form scheme://expr[;k=v&...][#fragment].
    No backend and no liv.has gate (pure; placed in liv.std for vocabulary
    coherence). Purely additive.
    ADD: liv.std.process gained streaming open(cmd,{on_stdout,on_stderr?,on_exit?})
    -> {write,close,kill} for long-lived, line-oriented child processes,
    complementing the existing one-shot system(cmd). Gated by the new capability
    has("process.stream") (true on both editors). The one-shot system() contract
    is unchanged. Purely additive.
    ADD: liv.std.mark gained range(buf,{line,col},{line,col},{hl}) -> id for
    intra-line column-span highlight (1-based inclusive, multi-line splits per
    line) via Neovim extmark end_col / Vim text-property end_col. Gated by the
    new capability has("mark.range") (Neovim always; Vim via text properties).
    The existing whole-line place() contract is unchanged. Purely additive.
```
