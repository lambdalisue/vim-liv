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
  return (source:gsub(PATTERN, function(call, openq, name, closeq)
    if vendored[name] then
      return call .. openq .. prefix .. "." .. name .. closeq
    end
    -- not vendored (plugin-owned or external): leave the match unchanged
  end))
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
