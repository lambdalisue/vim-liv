-- liv.tester._select — the selector mini-language (spec 0010). Pure Lua, editor-
-- independent, so L1 and L3 filter tests identically (cli.lua and _editor.lua
-- both require it). Borrowed in shape from probitas' tag-selector, restated in
-- liv's own vocabulary.
--
-- A SELECTOR string is a comma-separated list of TERMS, ANDed together. Each term:
--   `name:<pat>`  matches when the test's composed full title matches the Lua
--                 `<pat>` (case-insensitive).
--   `tag:<pat>`   matches when ANY of the test's composed tags matches `<pat>`
--                 (case-insensitive).
--   `<bare>`      shorthand for `name:<bare>`.
--   a leading `!` on any of the above negates that term.
-- Multiple selectors (passed as a list to `compile`) are ORed together. An empty
-- selector list matches everything.
--
-- Case-insensitivity is done by lowercasing both subject and pattern. This is a
-- deliberate 30-line simplification: it corrupts Lua's complement classes
-- (`%A`/`%S`/`%D`) inside patterns — acceptable for selectors, not documented as
-- a general matcher.

local M = {}

local function lower(s)
  return string.lower(s)
end

-- Build a single-term predicate `fun(title, tags): boolean`.
---@param term string
---@return fun(title: string, tags: string[]): boolean
local function parse_term(term)
  local negate = false
  if term:sub(1, 1) == "!" then
    negate = true
    term = term:sub(2)
  end

  local kind, pat = term:match("^(%w+):(.*)$")
  if kind ~= "name" and kind ~= "tag" then
    -- A bare word (or anything without a recognized `kind:` prefix) is name:.
    kind, pat = "name", term
  end
  pat = lower(pat)

  local predicate
  if kind == "tag" then
    predicate = function(_, tags)
      for _, tag in ipairs(tags) do
        if lower(tag):find(pat) then
          return true
        end
      end
      return false
    end
  else
    predicate = function(title, _)
      return lower(title):find(pat) ~= nil
    end
  end

  if negate then
    return function(title, tags)
      return not predicate(title, tags)
    end
  end
  return predicate
end

-- Compile one selector string into a predicate: all comma-separated terms ANDed.
---@param selector string
---@return fun(title: string, tags: string[]): boolean
function M.parse(selector)
  local terms = {}
  for raw in selector:gmatch("[^,]+") do
    -- Trim surrounding whitespace so "a, b" reads the same as "a,b".
    local term = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if term ~= "" then
      terms[#terms + 1] = parse_term(term)
    end
  end
  return function(title, tags)
    for _, predicate in ipairs(terms) do
      if not predicate(title, tags) then
        return false
      end
    end
    return true
  end
end

-- Compile a list of selector strings into one predicate: selectors ORed. An empty
-- list (or one with no string entries) matches everything. Non-string entries are
-- ignored — a bare `--select` (no `=value`) parses to boolean `true` under liv's
-- no-lookahead argument parser, and must degrade to "no filter", never crash
-- (matching how `--reporter`/`--editor` treat a bare flag as unset).
---@param selectors string[]
---@return fun(title: string, tags?: string[]): boolean
function M.compile(selectors)
  local predicates = {}
  if selectors then
    for _, selector in ipairs(selectors) do
      if type(selector) == "string" then
        predicates[#predicates + 1] = M.parse(selector)
      end
    end
  end
  if #predicates == 0 then
    return function()
      return true
    end
  end
  return function(title, tags)
    tags = tags or {}
    for _, predicate in ipairs(predicates) do
      if predicate(title, tags) then
        return true
      end
    end
    return false
  end
end

return M
