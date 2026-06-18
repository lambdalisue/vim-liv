-- Bundler static analysis (spec 0008): find string-literal `require`s and
-- compute the transitive dependency closure.
--
-- Pure Lua, editor-independent. Source is read through an injected resolver
-- (module name -> source string), so the closure logic is L1-testable without a
-- filesystem. Only string-literal requires are bundle-eligible; dynamic requires
-- must be declared in a manifest (see has_dynamic / spec 0008).

local M = {}

-- A literal require: `require` then an optional `(`, optional whitespace, then a
-- quoted module name. Matches both quote styles and the parenthesis-less form
-- (`require "foo"`). The opening quote is captured only to anchor the name scan.
local LITERAL = "require%s*%(?%s*(['\"])([^'\"]+)"

-- A dynamic require: `require(` followed by something that is not a quote — i.e.
-- a variable or expression rather than a string literal.
local DYNAMIC = "require%s*%(%s*[^'\"%s)]"

-- Extract the static literal module names, deduped, in first-seen order.
---@param source string Lua source text to scan.
---@return string[] names Static literal require targets, deduped, first-seen order.
function M.requires(source)
  local seen, out = {}, {}
  for _, name in source:gmatch(LITERAL) do
    if not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  return out
end

-- Does the source contain a dynamic (non-literal) require?
---@param source string Lua source text to scan.
---@return boolean has_dynamic Whether a dynamic (non-literal) require is present.
function M.has_dynamic(source)
  return source:match(DYNAMIC) ~= nil
end

local function sorted_keys(set)
  local keys = {}
  for k in pairs(set) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

-- The dependency closure result.
---@class liv.bundler.analyze.Closure
---@field modules string[] Sorted resolvable module names (incl. roots).
---@field external string[] Sorted unresolvable module names (recorded, not traversed).

-- Compute the transitive closure of modules reachable from `roots`.
--   resolve(name) -> source string, or nil if the module cannot be resolved.
-- Returns { modules = <sorted resolvable set incl. roots>,
--           external = <sorted unresolvable set, recorded but not traversed> }.
---@param roots string[] Module names to start traversal from.
---@param resolve fun(name: string): string? Resolve a module name to its source, or nil.
---@return liv.bundler.analyze.Closure closure The transitive dependency closure.
function M.closure(roots, resolve)
  local seen, external = {}, {}
  local queue = {}
  for _, r in ipairs(roots) do
    queue[#queue + 1] = r
  end
  while queue[1] do
    local name = table.remove(queue, 1)
    if not seen[name] and not external[name] then
      local source = resolve(name)
      if source == nil then
        external[name] = true
      else
        seen[name] = true
        for _, dep in ipairs(M.requires(source)) do
          if not seen[dep] then
            queue[#queue + 1] = dep
          end
        end
      end
    end
  end
  return { modules = sorted_keys(seen), external = sorted_keys(external) }
end

return M
