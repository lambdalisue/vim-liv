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
    Modules: liv.std.variable, liv.std.function, liv.std.mapping, liv.std.popup, liv.std.bufname, liv.std.process, liv.std.mark, liv.has, liv.lua.zlib.inflate, liv.lua.zlib.deflate, liv.lua.png.decode, liv.lua.png.encode, liv.lua.msgpack.pack, liv.lua.msgpack.unpack, liv.lua.color.rgb, liv.lua.color.hsl, liv.lua.color.xterm256, liv.lua.text.coerce, liv.lua.text.width
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
    ADD: liv.lua.uri was split from a single flat file (uri.lua) into concern
    leaves (uri/init.lua is now the barrel) so a consumer can bundle just one
    concern. The barrel (liv.lua.uri) keeps its full flat API unchanged —
    require("liv.lua.uri") behaves exactly as before, so this is purely additive
    (no consumer require path was renamed). New public leaf paths a consumer may
    require directly instead of the barrel:
      liv.lua.uri.percent — encode / decode (byte-wise percent coding, zero deps)
      liv.lua.uri.url     — parse / build (generic RFC 3986 split + inverse)
      liv.lua.uri.query   — encode_query / decode_query (requires the percent leaf)
    A percent-only bundle (require liv.lua.uri.percent) no longer ships parse/build
    or the query codec; a query-only bundle pulls percent but not parse/build.
    BREAKING: the zlib and png codec leaves were promoted from internal
    (underscore-prefixed) to public module paths so a consumer can bundle just
    one codec direction without pulling the whole family. The barrels
    (liv.lua.zlib, liv.lua.png) keep their inflate/deflate and decode/encode
    API unchanged — only direct requires of the old internal leaf paths must
    move:
      liv.lua.zlib._inflate -> liv.lua.zlib.inflate
      liv.lua.zlib._deflate -> liv.lua.zlib.deflate
      liv.lua.png._decode   -> liv.lua.png.decode
      liv.lua.png._encode   -> liv.lua.png.encode
    liv.lua.png._crc stays internal (a consumer never imports it directly).
    png.decode now requires only liv.lua.zlib.inflate and png.encode only
    liv.lua.zlib.deflate, so a decode-only bundle no longer ships deflate and an
    encode-only bundle no longer ships the heavier inflate.
    BREAKING: the msgpack pack/unpack leaves were promoted from internal
    (underscore-prefixed) to public module paths so a consumer can bundle just
    one direction (encode XOR decode) without pulling the other. The barrel
    (liv.lua.msgpack) keeps its encode/decode API unchanged — only direct
    requires of the old internal leaf paths must move:
      liv.lua.msgpack._pack   -> liv.lua.msgpack.pack
      liv.lua.msgpack._unpack -> liv.lua.msgpack.unpack
    msgpack.pack requires only liv.lua.value and liv.lua.compat, and
    msgpack.unpack only liv.lua.value, so an encode-only bundle no longer ships
    the decoder and a decode-only bundle no longer ships the encoder.
    ADD: liv.lua.color was split from a single flat file (color.lua) into concern
    leaves (color/init.lua is now the barrel) so a consumer can bundle just one
    concern. The barrel (liv.lua.color) keeps its full flat API unchanged —
    require("liv.lua.color") behaves exactly as before, so this is purely additive
    (no consumer require path was renamed). New public leaf paths a consumer may
    require directly instead of the barrel:
      liv.lua.color.rgb      — parse / to_hex / rgb / to_rgb (representation, zero deps)
      liv.lua.color.hsl      — hsl / to_hsl / lighten / darken (requires the rgb leaf)
      liv.lua.color.xterm256 — to_xterm256 / distance (requires the rgb leaf)
    An xterm256-only bundle (require liv.lua.color.xterm256) pulls the rgb leaf but
    no longer ships the HSL conversions; an HSL-only bundle pulls rgb but not the
    xterm256 quantizer.
    ADD: liv.lua.text was split from a single flat file (text.lua) into concern
    leaves (text/init.lua is now the barrel) so a consumer can bundle just one
    concern. The barrel (liv.lua.text) keeps its full flat API unchanged —
    require("liv.lua.text") behaves exactly as before, so this is purely additive
    (no consumer require path was renamed). New public leaf paths a consumer may
    require directly instead of the barrel:
      liv.lua.text.coerce — lines / aslist (content/argument coercion, zero deps)
      liv.lua.text.width  — chars / truncate / pad / align / wrap (display width)
    The mapping and popup backends, which coerce content/modes but never measure
    display width, now require liv.lua.text.coerce directly, so a mapping- or
    popup-only bundle no longer ships the heavier display-width algorithms.
```
