-- liv.std.keys — key NOTATION translation and key feeding (spec 0006).
-- Editor-dependent; selects a backend once at import.
--
-- Feeding keys and building rhs strings both need correct keycode/termcode
-- handling, and that handling differs between Vim and Neovim — authors should
-- never hand-roll "\x80..." escaping. This module absorbs the difference:
--
--   encode(notation) -> bytes   translate Vim key NOTATION ("<C-w>", "<CR>",
--     "<Esc>", "<Cmd>", "<Tab>", "<F1>", "<lt>", literal text) into the real
--     terminal byte sequence the editor expects. RETURNS BYTES, not notation.
--   feed(keys, opts?)           type `keys` (a NOTATION string, encoded for you)
--     into the input stream. opts.remap (default false) and opts.immediate
--     (default false) map to feedkeys mode flags.
--   send(keys, opts?)           feed with immediate defaulted on — the "do it now"
--     variant for tests/scripts that want the keys consumed synchronously.
--
-- The encode difference is the cross-editor seam: Neovim uses its native
-- replace-termcodes call; Vim evaluates a double-quoted string literal (the
-- editor's own notation->bytes mechanism). Both live in the backends; this file
-- owns the pure opts->mode-flag mapping and the encode->feed composition.
---@class liv.std.keys.feed_opts
---@field remap? boolean remap the fed keys as if typed through mappings (default false: noremap)
---@field immediate? boolean process the typeahead now instead of queueing it (default false)
---@class liv.std.keys
---@field encode fun(notation: string): string notation -> real terminal bytes
---@field feed fun(keys: string, opts?: liv.std.keys.feed_opts) type encoded keys into the input stream
---@field send fun(keys: string, opts?: liv.std.keys.feed_opts) feed with immediate defaulted on
local core = require("liv.core")

local backend = (core.is_nvim and require("liv.std.keys._nvim") or require("liv.std.keys._vim"))(
  core
)

-- Map feed opts to feedkeys mode flags. remap chooses 'm' (remap) vs 'n'
-- (noremap, the default); immediate appends 'x' so the typeahead is processed at
-- once. The bytes are already real termcodes (encode ran first), so no escaping
-- flag is involved.
---@param opts liv.std.keys.feed_opts
---@return string
local function flags_of(opts)
  return (opts.remap and "m" or "n") .. (opts.immediate and "x" or "")
end

---@class liv.std.keys
local M = {}

---Translate Vim key NOTATION into the real terminal byte sequence.
---@param notation string e.g. "<C-w>", "<CR>", "<Esc>", "<lt>", or literal text
---@return string bytes the encoded terminal bytes (NOT notation)
function M.encode(notation)
  return backend.encode(notation)
end

---Feed `keys` (a NOTATION string, encoded internally) into the input stream.
---@param keys string key notation to type
---@param opts? liv.std.keys.feed_opts
function M.feed(keys, opts)
  opts = opts or {}
  backend.feed(backend.encode(keys), flags_of(opts))
end

---Feed `keys` with `immediate` defaulted on (process the typeahead now).
---An explicit `opts.immediate = false` still wins, so callers can opt back out.
---@param keys string key notation to type
---@param opts? liv.std.keys.feed_opts
function M.send(keys, opts)
  opts = opts or {}
  -- Build a fresh opts rather than writing back into the caller's table: a
  -- reused opts must not be silently flipped to immediate for later feed calls.
  local immediate = opts.immediate
  if immediate == nil then
    immediate = true
  end
  return M.feed(keys, { remap = opts.remap, immediate = immediate })
end

return M
