-- liv.std.keys Neovim backend: native replace-termcodes + feedkeys (this file
-- only runs on Neovim), each bound once via core.marshaled so calls use plain Lua
-- values and marshaling can't be forgotten.
--
-- encode uses nvim_replace_termcodes(notation, from_part=true, do_lt=true,
-- special=true): the canonical native notation->bytes call, so "<CR>"/"<Esc>"/
-- "<C-w>"/"<lt>" become the exact bytes the editor consumes; literal text passes
-- through. feed then types those bytes via nvim_feedkeys with escape_ks=false —
-- the bytes are ALREADY real termcodes, so re-escaping them would corrupt the
-- input (the one easy-to-miss invariant of the native call).
return function(core)
  local replace_termcodes = core.marshaled(vim.api.nvim_replace_termcodes)
  local feedkeys = core.marshaled(vim.api.nvim_feedkeys)

  local M = {}

  ---@param notation string
  ---@return string
  function M.encode(notation)
    return replace_termcodes(notation, true, true, true)
  end

  ---@param encoded string already-encoded terminal bytes (from encode)
  ---@param flags string feedkeys mode flags
  function M.feed(encoded, flags)
    -- escape_ks=false: encoded already holds real termcodes; do not re-escape.
    feedkeys(encoded, flags, false)
  end

  return M
end
