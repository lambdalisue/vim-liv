-- liv.lua.argument.parse — the parse side of the command-argument family (spec
-- 0009). Pure Lua, editor-independent, deterministic, L1-testable. liv.std.command
-- handlers receive a RAW argument string, and every plugin would otherwise
-- re-implement flag parsing; this owns liv's own vocabulary for it (modeled on
-- Vim's `:command` arg conventions + `:edit ++opt` long-options), NOT a copy of
-- any one editor's shape.
--
-- This leaf is the common case: it tokenizes (`split`) and classifies (`parse`)
-- command arguments and never reaches for the `format` inverse, so a parse-only
-- consumer vendors only this file, not the format side.
--
-- `parse` is the core. It returns THREE values — `opts`, `flags`, `rest` — and is
-- a GENERIC parser: it never validates against a schema, so unknown opts/flags are
-- kept verbatim (a separate validate step is out of scope).
--
-- Grammar (classified per token, in this order):
--   `--`        (exactly)      terminator — everything AFTER it is positional
--                              `rest`, verbatim, even if it looks like a flag/opt.
--   `++name`    / `++name=v`   a Vim-style long-option `opt` (the `++` Vim uses for
--                              `:edit ++enc=...`). No `=` → boolean true.
--   `--name`    / `--name=v`   a long `flag`. No `=` → boolean true.
--   `-x`        (len > 1)      a short `flag`, always boolean true. Short-flag
--                              CLUSTERING is out of scope: `-abc` is ONE flag key
--                              `abc`, not three flags — documented, never a crash.
--   `-`         (bare)         positional `rest`.
--   anything else              positional `rest`.
--
-- Disambiguation: a value is supplied ONLY via `=`. A `=`-less long flag/opt is
-- ALWAYS boolean true; the parser never consumes the following token as its value
-- (no lookahead). So `--foo bar` is `flags.foo = true` plus positional `bar`. Only
-- the FIRST `=` splits, so `--expr=a=b=c` keeps the value `a=b=c`.
--
-- Repeats collect (mirroring liv.lua.uri.query.decode_query): the first occurrence of a
-- key is a scalar, the second promotes it to an array preserving order, so
-- `--inc=a --inc=b` → `{ "a", "b" }` and `--foo --foo=bar` → `{ true, "bar" }`.
-- This applies to both `opts` and `flags`.

local M = {}

-- Tokenize a raw argument string honoring simple quoting. Quoting rules:
--   * a run of unquoted whitespace separates tokens;
--   * single quotes `'…'` and double quotes `"…"` group their contents into one
--     token and are REMOVED from the result (no special handling inside — a quote
--     is purely a grouping boundary);
--   * a backslash escapes the very next character in ANY context (so `a\ b` is one
--     token "a b", and `\'` is a literal quote);
--   * empty quotes `''` / `""` still emit an empty-string token;
--   * an unterminated quote is lenient: the run so far is emitted as a token.
-- Operates on bytes via string.byte/sub, so it is multibyte-safe (it never splits
-- inside a UTF-8 sequence — only ASCII space/tab/quote/backslash are structural).
---@param str string
---@return string[] tokens
function M.split(str)
  local tokens = {}
  local buf = {}
  local has_token = false -- distinct from `#buf > 0` so `''` emits ""
  local quote = nil -- nil, "'" or '"'
  local i = 1
  local n = #str

  local function flush()
    if has_token then
      tokens[#tokens + 1] = table.concat(buf)
      buf = {}
      has_token = false
    end
  end

  while i <= n do
    local c = str:sub(i, i)
    if c == "\\" and i < n then
      -- Escape: take the next char literally, in or out of quotes.
      buf[#buf + 1] = str:sub(i + 1, i + 1)
      has_token = true
      i = i + 2
    elseif quote then
      if c == quote then
        quote = nil -- closing quote; group boundary, drop it
      else
        buf[#buf + 1] = c
      end
      has_token = true
      i = i + 1
    elseif c == "'" or c == '"' then
      quote = c -- opening quote; group boundary, drop it
      has_token = true
      i = i + 1
    elseif c == " " or c == "\t" or c == "\n" or c == "\r" then
      flush()
      i = i + 1
    else
      buf[#buf + 1] = c
      has_token = true
      i = i + 1
    end
  end
  flush()

  return tokens
end

-- Insert `value` under `key` in `dest`, collecting repeats into an array (first
-- occurrence scalar, second promotes to a list preserving order). Shared by opts
-- and flags; mirrors liv.lua.uri.query.decode_query's repeat handling.
---@param dest table<string, any>
---@param key string
---@param value string|boolean
local function collect(dest, key, value)
  local existing = dest[key]
  if existing == nil then
    dest[key] = value
  elseif type(existing) == "table" then
    existing[#existing + 1] = value
  else
    dest[key] = { existing, value }
  end
end

-- Split a `name[=value]` body into its key and value. With no `=` the value is
-- boolean true; with `=` only the FIRST `=` splits (so the value may contain `=`),
-- and an empty value (`name=`) is the empty string.
---@param body string
---@return string key, string|boolean value
local function key_value(body)
  local eq = body:find("=", 1, true)
  if not eq then
    return body, true
  end
  return body:sub(1, eq - 1), body:sub(eq + 1)
end

-- Parse command arguments into `opts`, `flags`, `rest`.
--
-- `input` is EITHER a raw string (tokenized by `split`, honoring quotes) OR an
-- array of already-split tokens (used verbatim, NOT re-split — so a token may
-- itself contain spaces).
---@param input string|string[]
---@return table<string, string|boolean|(string|boolean)[]> opts `++name[=value]` long-options
---@return table<string, string|boolean|(string|boolean)[]> flags `-f` / `--name[=value]` flags
---@return string[] rest positional residue, in order
function M.parse(input)
  local tokens = type(input) == "table" and input or M.split(input)

  local opts = {}
  local flags = {}
  local rest = {}
  local positional_only = false -- set once `--` is seen

  for _, token in ipairs(tokens) do
    if positional_only then
      rest[#rest + 1] = token
    elseif token == "--" then
      positional_only = true
    elseif token:sub(1, 2) == "++" then
      local key, value = key_value(token:sub(3))
      collect(opts, key, value)
    elseif token:sub(1, 2) == "--" then
      local key, value = key_value(token:sub(3))
      collect(flags, key, value)
    elseif token:sub(1, 1) == "-" and #token > 1 then
      -- Short flag, always boolean. Multi-char is treated as one key (clustering
      -- is out of scope) rather than rejected.
      collect(flags, token:sub(2), true)
    else
      -- Bare "-" and everything else are positional.
      rest[#rest + 1] = token
    end
  end

  return opts, flags, rest
end

return M
