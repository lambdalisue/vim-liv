-- liv.std.exec — run a block of vimscript (spec 0006). `liv.core.cmd` runs ONE Ex
-- command; an author with a multi-line block of vimscript (especially one using
-- leading-backslash line continuations, or a block construct like :if/:for/:try/
-- :function) has no single helper. `exec` fills that gap: it joins continuation
-- lines, then runs the whole block as ONE script via `core.cmd`.
--
-- The block runs as one script — NOT one Ex command per line — because a block
-- construct's body only executes within the block's parse context: feeding the
-- lines to `core.cmd` one at a time opens an `:if`/`:for` and then parses the
-- next line in a fresh context, dropping the body (and corrupting later parsing).
-- `core.cmd` already accepts a newline-joined multi-line script and preserves
-- block context across it on both editors (vim.command / nvim_command), so a
-- single `core.cmd(joined)` runs flat sequences AND blocks correctly.
--
-- Editor-dependent (it runs Ex commands through core), but there is NO backend
-- split: `core.cmd` already absorbs the cross-editor difference, so the join logic
-- is identical on both editors (the `hash`/`text` "single module" precedent). No
-- `liv.std.has` gate — running Ex commands is a base capability on both editors.
--
-- Continuation-join rule (Vim's line-continuation, see `:help line-continuation`):
-- a line whose first non-blank character is a backslash `\` continues the previous
-- line. Its leading whitespace and the leading `\` are stripped, and the remainder
-- is appended to the previous line with NO separator inserted (so
-- `"let x =\n\\ 1"` becomes `"let x = 1"`). A continuation as the very first line
-- has nothing to attach to, so it stands on its own (matching Vim, which errors on
-- such input only when the command is invalid).
local core = require("liv.core")

-- Split a string into lines on "\n" (also tolerating "\r\n"). Kept local and
-- simple: exec only needs newline splitting, not full pattern handling.
---@param source string
---@return string[]
local function split_lines(source)
  local lines = {}
  for line in (source .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = (line:gsub("\r$", ""))
  end
  return lines
end

-- Join Vim leading-backslash continuation lines onto their predecessor. A line
-- matching `^%s*\` is a continuation: strip its leading blanks and the `\`, then
-- append the remainder to the previous joined line with no separator.
---@param lines string[]
---@return string[]
local function join_continuations(lines)
  local joined = {}
  for _, line in ipairs(lines) do
    local cont = line:match("^%s*\\(.*)$")
    if cont ~= nil and #joined > 0 then
      joined[#joined] = joined[#joined] .. cont
    else
      joined[#joined + 1] = line
    end
  end
  return joined
end

-- Run a block of vimscript. `source` is a multi-line string OR an array of lines;
-- leading-backslash continuation lines are joined to the previous line, then the
-- whole block runs as ONE script via `core.cmd` (so block constructs like :if/:for
-- keep their parse context). Errors propagate (pcall-able), as with `core.cmd`.
-- The module is a single callable (the spec's `liv.std.exec` single-verb shape,
-- like `liv.std.has`).
---@param source string|string[]
return function(source)
  local lines
  if type(source) == "table" then
    lines = source
  else
    lines = split_lines(source)
  end
  core.cmd(table.concat(join_continuations(lines), "\n"))
end
