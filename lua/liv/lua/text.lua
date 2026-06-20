-- liv.lua.text — pure text/argument coercion helpers (spec 0006).
--
-- Editor-independent: these carry no editor access, so the editor-dependent
-- backends (popup, mapping) share one implementation instead of each hand-rolling
-- a byte-identical copy. Kept here in liv.lua because the logic is deterministic
-- pure Lua, L1-testable, and identical on every host.

local M = {}

-- Normalize display content into a list of lines: a list is returned as-is; a
-- string is split on "\n" (a trailing newline yields a trailing empty line, and
-- an empty string yields a single empty line, matching how the editors render a
-- single blank row).
---@param content string|string[]
---@return string[] lines
function M.lines(content)
  if type(content) == "table" then
    return content
  end
  local out = {}
  for line in (content .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = line
  end
  return out
end

-- Coerce a string-or-list argument into a plain list to iterate. A list is
-- returned as-is; a scalar (e.g. a single mode "n") is wrapped into a
-- one-element list. Used to accept `modes` as either "n" or { "n", "i" }.
---@generic T
---@param value T|T[]
---@return T[] list
function M.aslist(value)
  if type(value) == "table" then
    return value
  end
  return { value }
end

-- Display-width string operations.
--
-- Lua has no terminal display-width primitive (`#str` is bytes, not columns; an
-- East-Asian wide char occupies two columns), so these algorithms are kept pure
-- and editor-independent: each takes an injected `width_fn(s) -> integer` that
-- measures a string's display columns. `liv.std.text` wires the editor's real
-- `strdisplaywidth()` in; tests inject a fake. Slicing always lands on UTF-8
-- code-point boundaries (never mid-byte): we walk code points via `chars` and
-- measure each with the injected width function.

-- Byte length of the UTF-8 code point whose leading byte is `b`. Determined by
-- value range only (no bitwise operators, which are not in the 5.1 dialect):
-- 0x00-0x7F → 1, 0xC0-0xDF → 2, 0xE0-0xEF → 3, 0xF0-0xF7 → 4. A stray
-- continuation byte (0x80-0xBF) or an out-of-range leader is treated as a lone
-- byte so the iterator always makes progress on malformed input.
local function leading_byte_length(b)
  if b < 0x80 then
    return 1
  elseif b >= 0xF0 and b <= 0xF7 then
    return 4
  elseif b >= 0xE0 and b <= 0xEF then
    return 3
  elseif b >= 0xC0 and b <= 0xDF then
    return 2
  end
  return 1
end

-- Iterate a string by UTF-8 code point. Stateless iterator usable as
-- `for _, ch in text.chars(s) do ... end`; each `ch` is the substring of one
-- code point, so concatenating every `ch` reproduces the input exactly.
---@param s string
---@return fun(state: table, i: integer): integer?, string?
---@return table state
---@return integer start
function M.chars(s)
  local function iter(state, i)
    if i > #state.s then
      return nil
    end
    local len = leading_byte_length(string.byte(state.s, i))
    return i + len, string.sub(state.s, i, i + len - 1)
  end
  return iter, { s = s }, 1
end

-- Resolve the optional `(opts?, width_fn)` tail: callers may omit `opts` and
-- pass `width_fn` directly. Returns `opts` (or an empty table) and `width_fn`.
local function resolve(opts, width_fn)
  if type(opts) == "function" then
    return {}, opts
  end
  return opts or {}, width_fn
end

-- Truncate `str` to fit `max_width` display columns, marking truncation with an
-- ellipsis whose own width is counted so the result never exceeds `max_width`.
-- opts.ellipsis defaults to "…"; opts.side is "right" (default), "left", or
-- "center". If the ellipsis itself cannot fit, the text is hard-truncated to the
-- budget with no ellipsis. Slicing is on code-point boundaries.
---@param str string
---@param max_width integer
---@param opts? { ellipsis?: string, side?: string }
---@param width_fn fun(s: string): integer
---@return string
function M.truncate(str, max_width, opts, width_fn)
  opts, width_fn = resolve(opts, width_fn)
  if width_fn(str) <= max_width then
    return str
  end
  local ellipsis = opts.ellipsis
  if ellipsis == nil then
    ellipsis = "…"
  end
  local side = opts.side or "right"

  -- Take code points from the front of `s` up to `budget` columns.
  local function take_front(s, budget)
    local acc, used = {}, 0
    for _, ch in M.chars(s) do
      local cw = width_fn(ch)
      if used + cw > budget then
        break
      end
      acc[#acc + 1] = ch
      used = used + cw
    end
    return table.concat(acc), used
  end

  -- Take code points from the back of `s` up to `budget` columns.
  local function take_back(s, budget)
    local chs = {}
    for _, ch in M.chars(s) do
      chs[#chs + 1] = ch
    end
    local start, used = #chs + 1, 0
    for i = #chs, 1, -1 do
      local cw = width_fn(chs[i])
      if used + cw > budget then
        break
      end
      start = i
      used = used + cw
    end
    return table.concat(chs, "", start, #chs), used
  end

  local ell_w = width_fn(ellipsis)
  -- Not enough room for the ellipsis: hard-truncate without it.
  if ell_w > max_width then
    if side == "left" then
      return (take_back(str, max_width))
    end
    return (take_front(str, max_width))
  end

  local budget = max_width - ell_w
  if side == "left" then
    return ellipsis .. (take_back(str, budget))
  elseif side == "center" then
    -- Keep a head and a tail; head gets the larger half on an odd budget.
    local head_budget = budget - math.floor(budget / 2)
    local tail_budget = budget - head_budget
    local head = take_front(str, head_budget)
    local tail = take_back(str, tail_budget)
    return head .. ellipsis .. tail
  end
  return (take_front(str, budget)) .. ellipsis
end

-- Pad `str` with a fill character to reach `width` display columns. opts.side is
-- "right" (default), "left", or "both"; opts.fill defaults to " ". If `str` is
-- already at or beyond `width`, it is returned unchanged.
---@param str string
---@param width integer
---@param opts? { side?: string, fill?: string }
---@param width_fn fun(s: string): integer
---@return string
function M.pad(str, width, opts, width_fn)
  opts, width_fn = resolve(opts, width_fn)
  local deficit = width - width_fn(str)
  if deficit <= 0 then
    return str
  end
  local fill = opts.fill or " "
  local side = opts.side or "right"
  local fill_w = width_fn(fill)
  if fill_w <= 0 then
    return str
  end

  local function fill_for(cols)
    return string.rep(fill, math.floor(cols / fill_w))
  end

  if side == "left" then
    return fill_for(deficit) .. str
  elseif side == "both" then
    local left = math.floor(deficit / 2)
    return fill_for(left) .. str .. fill_for(deficit - left)
  end
  return str .. fill_for(deficit)
end

-- Align `str` within `width` display columns. opts.side is "left" (pad right),
-- "right" (pad left), or "center" (pad both). Built on `pad`.
---@param str string
---@param width integer
---@param opts? { side?: string, fill?: string }
---@param width_fn fun(s: string): integer
---@return string
function M.align(str, width, opts, width_fn)
  opts, width_fn = resolve(opts, width_fn)
  local side = opts.side or "left"
  local pad_side = "right"
  if side == "right" then
    pad_side = "left"
  elseif side == "center" then
    pad_side = "both"
  end
  return M.pad(str, width, { side = pad_side, fill = opts.fill }, width_fn)
end

-- Break `str` into lines each at most `width` display columns. Breaks on spaces
-- where possible; a run too long to fit is hard-broken on code-point boundaries
-- (never mid-byte). Space-broken lines rejoin with a single space; a hard-broken
-- run rejoins with no separator.
---@param str string
---@param width integer
---@param width_fn fun(s: string): integer
---@return string[]
function M.wrap(str, width, width_fn)
  local lines = {}
  local function emit(line)
    lines[#lines + 1] = line
  end

  -- Hard-break a word that does not fit on its own, on code-point boundaries.
  local function break_word(word)
    local pieces, cur, used = {}, {}, 0
    for _, ch in M.chars(word) do
      local cw = width_fn(ch)
      if used + cw > width and used > 0 then
        pieces[#pieces + 1] = table.concat(cur)
        cur, used = {}, 0
      end
      cur[#cur + 1] = ch
      used = used + cw
    end
    if #cur > 0 then
      pieces[#pieces + 1] = table.concat(cur)
    end
    return pieces
  end

  local current = nil
  for word in (str .. " "):gmatch("(.-) ") do
    local pieces = break_word(word)
    for i = 1, #pieces do
      local piece = pieces[i]
      if current == nil then
        current = piece
      elseif width_fn(current) + 1 + width_fn(piece) <= width then
        current = current .. " " .. piece
      else
        emit(current)
        current = piece
      end
    end
  end
  if current ~= nil then
    emit(current)
  end
  return lines
end

return M
