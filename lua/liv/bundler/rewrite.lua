-- Bundler require rewriting (spec 0008). Pure Lua, editor-independent.
--
-- After the closure is vendored under a plugin-owned prefix, every inter-module
-- `require("liv.std.buffer")` must become `require("<plugin>.vendor.liv.std.buffer")`
-- so the vendored copy is self-contained and cannot collide (in package.loaded)
-- with another plugin's vendored liv. Only requires whose target is in the
-- vendored set are rewritten — matched on the exact module name, never a
-- substring — so the plugin's own modules and external deps are left untouched.
local M = {}

-- `require` + optional `(` + optional ws, then a quoted module name. The opening
-- and closing quotes are captured so the (possibly different) style is preserved.
local PATTERN = "(require%s*%(?%s*)(['\"])([^'\"]+)(['\"])"

-- Rewrite vendored requires in `source`.
---@param source string Lua source text.
---@param vendored table<string,boolean> set of module names that were vendored.
---@param prefix string the plugin-owned prefix (e.g. "myplugin.vendor").
---@return string rewritten
function M.rewrite(source, vendored, prefix)
  return (
    source:gsub(PATTERN, function(call, openq, name, closeq)
      if vendored[name] then
        return call .. openq .. prefix .. "." .. name .. closeq
      end
      -- not vendored (plugin-owned or external): leave the match unchanged
    end)
  )
end

-- Rewrite vendored autoload `#`-name references in `source`. Each `stem` (e.g.
-- "liv#std#dispatch") is the autoload prefix of a vendored Vim 9 companion's
-- functions; the vendored copy lives at a relocated autoload path, so prepend the
-- plugin's `#`-prefix to every `stem#...` occurrence — the .lua then calls the
-- vendored functions ("myplugin#vendor#liv#std#dispatch#Invoke") and Vim
-- auto-sources the relocated file. `#`/`_` are literal in Lua patterns and stems
-- are `[%w_#]`, so a stem is a safe literal pattern; requiring a trailing `#`
-- (a function segment always follows) keeps a stem from matching a longer name.
--
-- Why not: unlike `rewrite` (anchored on a `require(...)` call site), this is a
-- deliberate whole-source substring replace, NOT anchored to string literals. It
-- is correct *because it over-matches safely*: a `#` is illegal in Lua code, so a
-- `stem#...` can only occur inside a string (an autoload call) or a comment, and
-- rewriting a comment is harmless. Anchoring on a quote instead would fail
-- DANGEROUS: the autoload name is embedded mid-string at several call sites
-- (e.g. `"<Cmd>call liv#std#dispatch#Invoke(...)"`), so a quote-anchored rewrite
-- would silently MISS them, leaving an unprefixed name that collides with another
-- vendored liv at runtime. For a liv-OWNED namespace no consumer subsets, harmless
-- over-rewrite beats silent under-rewrite, so the whole-source replace stands.
---@param source string Lua source text.
---@param stems string[] autoload name stems that were vendored (`#`-joined).
---@param hash_prefix string the plugin-owned `#`-prefix (e.g. "myplugin#vendor").
---@return string rewritten
function M.rewrite_autoload(source, stems, hash_prefix)
  local out = source
  for _, stem in ipairs(stems) do
    out = out:gsub(stem .. "#", hash_prefix .. "#" .. stem .. "#")
  end
  return out
end

-- Build the vendored-name set from the closure's module list.
---@param modules string[]
---@return table<string,boolean>
function M.name_set(modules)
  local set = {}
  for _, m in ipairs(modules) do
    set[m] = true
  end
  return set
end

return M
