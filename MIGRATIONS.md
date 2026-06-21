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
    Modules: liv.std.variable, liv.std.function, liv.std.option, liv.std.mapping, liv.std.popup, liv.std.exec, liv.std.window, liv.std.autocmd, liv.std.bufname, liv.std.process, liv.std.mark, liv.has, liv.lua.zlib.inflate, liv.lua.zlib.deflate, liv.lua.png.decode, liv.lua.png.encode, liv.lua.msgpack.pack, liv.lua.msgpack.unpack, liv.lua.color.rgb, liv.lua.color.hsl, liv.lua.color.xterm256, liv.lua.text.coerce, liv.lua.text.width, liv.lua.argument.parse, liv.lua.argument.format
    BREAKING: std modules renamed to align with denops/std vocabulary. API
    signatures are unchanged — only the module path/name moved. Update requires:
      liv.std.var   -> liv.std.variable
      liv.std.map   -> liv.std.mapping
      liv.std.float -> liv.std.popup
      liv.std.fn    -> liv.std.function
    The liv.has capability keys for popup windows were renamed to match:
      has("float")        -> has("popup")
      has("float.border") -> has("popup.border")
    BREAKING: liv.std.popup is now buffer-backed (denops/std parity). open()
    takes a caller-owned bufnr instead of content lines; create the buffer with
    liv.std.buffer and write to it (the popup follows the buffer live). The popup
    stays non-focusable/non-interactive (a display overlay) and closing it leaves
    the buffer alive (caller-managed lifecycle). Added config(win,opts) for
    in-place retitle/resize/reposition (move/resize are thin wrappers over it).
    Migrate:
      open(lines, opts)  ->  local b = buffer.create({ scratch = true })
                             buffer.set_lines(b, 1, 1, lines)
                             open(b, opts)
    has("popup")/has("popup.border") unchanged.
    FIX: liv.std.exec now runs its source as ONE script instead of one Ex
    command per line, so multi-line block constructs (:if/:for/:while/:try/
    :function/:def) execute correctly — previously a per-line loop opened the
    block then parsed the next line in a fresh context, silently dropping the
    body. Flat statement sequences and backslash-continuation behave as before;
    no signature change.
    ADD: liv.std.window gained open(bufnr, opts?) -> win and set_buffer(win,
    bufnr). open displays a caller-owned buffer (create via liv.std.buffer) in a
    NEW split window (opts: split=above|below|left|right, size, focus) and returns
    its handle — the normal-split analogue of liv.std.popup's float overlay, so
    closing the window never wipes the caller's buffer. set_buffer swaps the
    buffer shown in a window. Purely additive.
    ADD: liv.std.autocmd gained clear(group) — remove every subscription
    registered under a group in one call (the canonical wipe-augroup-and-
    re-register reload idiom, without retaining each sub). A no-op for a group
    with no live subscriptions. Purely additive.
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
    CHANGE: liv.std.option's generated RUNTIME metadata (the _generated.lua
    modules) was slimmed from a full {type,scope} record per option (~436 entries)
    to a SET of boolean option names ({ [name] = true }, ~142 entries). The
    runtime only needs to know whether an option is boolean (to coerce a 0/1 get
    into a Lua boolean); set-side formatting now keys off the passed Lua value's
    own type, and option scope was never read at runtime. The per-option Lua
    TYPE is retained in the require-free LuaLS _generated_annotations.lua (which
    drives completion/type-checks), so DX is unchanged; the scope field, never
    consumed at runtime or for completion (init types every option under all
    g/b/w/l scopes), is dropped. Consumer behavior is unchanged (the public
    option API and value coercion are identical); a consumer that directly
    required liv.std.option._generated for its records — never a public
    contract — would need to read the annotations instead.
    ADD: liv.lua.argument was split from a single flat file (argument.lua) into
    parse/format leaves (argument/init.lua is now the barrel) so a parse-only
    consumer never vendors the rarely-used format inverse. The barrel
    (liv.lua.argument) keeps its full flat API unchanged — require("liv.lua.argument")
    behaves exactly as before, so this is purely additive (no consumer require
    path was renamed). New public leaf paths a consumer may require directly
    instead of the barrel:
      liv.lua.argument.parse  — split / parse (quote-aware tokenizer + classifier, zero deps)
      liv.lua.argument.format — format (rebuild a command line from a parse, zero deps)
    The two sides are fully independent (parse never calls format and vice
    versa), so a parse-only bundle (require liv.lua.argument.parse) no longer
    ships the format inverse.
    ADD: liv.lua.base64 was split from a single flat file (base64.lua) into
    encode/decode leaves (base64/init.lua is now the barrel) so an encode-only
    consumer never vendors the decoder (and vice versa). The barrel
    (liv.lua.base64) keeps its full flat API unchanged — require("liv.lua.base64")
    behaves exactly as before, so this is purely additive (no consumer require
    path was renamed). New public leaf paths a consumer may require directly
    instead of the barrel:
      liv.lua.base64.encode — encode / encode_url (RFC 4648 §4/§5 encoder)
      liv.lua.base64.decode — decode / decode_url (one decoder serves both alphabets)
    Both leaves share the internal liv.lua.base64._tables alphabet helper (kept
    underscore-prefixed; a consumer never imports it directly). The two sides are
    fully independent (encode never calls decode and vice versa), so an
    encode-only bundle (require liv.lua.base64.encode) no longer ships the decoder.
```
