-- liv.std.keys Vim backend: encode via the editor's own double-quoted-string
-- evaluation, feed via feedkeys (bound once as a marshaled reference).
--
-- In a Vim double-quoted string, "\<CR>" / "\<Esc>" / "\<C-w>" expand to the real
-- terminal bytes (the editor's native notation->bytes mechanism; the same path
-- ui/_vim.lua relies on via core.eval([["\<CR>"]])). So encode wraps the notation
-- in a double-quoted literal and evaluates it. To turn each "<...>" token into a
-- key, the literal must read `"\<...>"`, so a bare `<` is rewritten to `\<` —
-- correct because in Vim/Neovim notation a literal less-than is always written
-- `<lt>`, never a bare `<`. Backslashes and double-quotes in the input are
-- escaped first so arbitrary text round-trips as itself.
return function(core)
  local feedkeys = core.marshaled(vim.fn.feedkeys)

  local M = {}

  -- Escape `notation` into the body of a Vim double-quoted string literal. Order
  -- matters: backslash first (so later-inserted backslashes are not re-escaped),
  -- then the double-quote, then `<` -> `\<` (which arms each notation token).
  local function quote_body(notation)
    local body = notation:gsub("\\", "\\\\")
    body = body:gsub('"', '\\"')
    body = body:gsub("<", "\\<")
    return body
  end

  ---@param notation string
  ---@return string
  function M.encode(notation)
    return core.eval('"' .. quote_body(notation) .. '"')
  end

  ---@param encoded string already-encoded terminal bytes (from encode)
  ---@param flags string feedkeys mode flags
  function M.feed(encoded, flags)
    feedkeys(encoded, flags)
  end

  return M
end
