-- Bundler vendoring (spec 0008). Computes the closure of `roots`, then writes each
-- module's source — with its inter-module requires rewritten to the plugin-owned
-- prefix — into the plugin's vendor tree, and records a lockfile.
--
-- Editor-independent: all filesystem access goes through an injected `fs` table
-- ({ write(path, content), clean(dir) }) and all source access through an injected
-- `resolver` ({ read(name) -> content?, locate(name) -> relpath? }). So the whole
-- thing is L1-testable with in-memory fakes, and the same code runs standalone
-- (io-backed fs) or inside the editor (liv.std.fs-backed).
local analyze = require("liv.bundler.analyze")
local rewrite = require("liv.bundler.rewrite")
local lockfile = require("liv.bundler.lockfile")

local M = {}

-- opts:
--   roots    string[]            modules to bundle (+ their transitive closure)
--   resolver { read, locate }    source access
--   fs       { write, clean }    filesystem sink
--   target   string              the consumer plugin's root directory
--   plugin   string              the plugin's require name (e.g. "myplugin")
--   source   string?             source kind recorded in the lockfile (default "path")
--   version  string?             version recorded in the lockfile
---@param opts table
---@return { modules: string[], external: string[], lock: table }
function M.vendor(opts)
  local resolver, fs = opts.resolver, opts.fs
  local prefix = opts.plugin .. ".vendor"
  local plugin_path = (opts.plugin:gsub("%.", "/"))
  local vendor_root = opts.target .. "/lua/" .. plugin_path .. "/vendor"
  -- Vim 9 autoload companions are relocated under the consumer's autoload/ tree so
  -- their `#`-names match the rewritten .lua references (e.g.
  -- myplugin#vendor#liv#std#process#Start) and Vim auto-sources them; the `#`-form
  -- of the require prefix is the autoload prefix.
  local autoload_root = opts.target .. "/autoload/" .. plugin_path .. "/vendor"
  local hash_prefix = (prefix:gsub("%.", "#"))

  local closure = analyze.closure(opts.roots, resolver.read, resolver.manifest)
  local vendored = rewrite.name_set(closure.modules)

  -- The autoload name stems that were vendored (e.g. "liv/std/dispatch.vim" ->
  -- "liv#std#dispatch"), so the .lua references to them can be rewritten to the
  -- relocated, plugin-prefixed names.
  local autoload_stems = {}
  for _, files in pairs(closure.companions_autoload) do
    for _, entry in ipairs(files) do
      autoload_stems[#autoload_stems + 1] = (entry:gsub("%.vim$", ""):gsub("/", "#"))
    end
  end

  fs.clean(vendor_root) -- clean reinstall: never leave a stale vendored module
  fs.clean(autoload_root) -- likewise for relocated autoload companions

  local lock = {
    meta = {
      plugin = opts.plugin,
      source = opts.source or "path",
      from = opts.from,
      ref = opts.ref,
      roots = opts.roots,
    },
    modules = {},
  }
  for _, name in ipairs(closure.modules) do
    local relpath = resolver.locate(name)
    local content = resolver.read(name)
    -- Rewrite inter-module requires AND vendored autoload `#`-name references; the
    -- lockfile hash is of the ORIGINAL source (to track the upstream), not the
    -- rewritten copy.
    local rewritten = rewrite.rewrite_autoload(
      rewrite.rewrite(content, vendored, prefix),
      autoload_stems,
      hash_prefix
    )
    fs.write(vendor_root .. "/" .. relpath, rewritten)
    lock.modules[name] = {
      source = opts.source or "path",
      version = opts.version,
      hash = lockfile.hash(content),
    }

    -- Copy declared companion files (e.g. a Vim 9 `.vim`) beside the module,
    -- verbatim — they are not Lua, so requires are not rewritten. The companion
    -- path is relative to the module's directory.
    local files = closure.companions[name]
    if files then
      local dir = relpath:match("^(.*)/[^/]+$") or ""
      for _, comp in ipairs(files) do
        local rel = (dir ~= "" and (dir .. "/") or "") .. (comp:gsub("^%./", ""))
        -- Anchor the companion read to the module's own root (provenance), so a
        -- multi-root resolver cannot pair this module's Lua body with another
        -- root's same-named companion.
        local raw = resolver.read_raw(rel, name)
        if raw then
          fs.write(vendor_root .. "/" .. rel, raw)
        end
      end
    end

    -- Relocate declared autoload companions into the consumer's autoload/ tree,
    -- verbatim — they carry no hardcoded prefix (their function/forwarder prefixes
    -- are derived at runtime from the script's own path), so only the FILE path is
    -- rewritten (liv/... -> <plugin>/vendor/liv/...). Read from the source root's
    -- autoload/ (a sibling of lua/, hence "../autoload/").
    local autoload = closure.companions_autoload[name]
    if autoload then
      for _, entry in ipairs(autoload) do
        -- `name` anchors the read to the module's own root (provenance): the
        -- relocated companion must come from the same root as the .lua body.
        local raw = resolver.read_raw("../autoload/" .. entry, name)
        if raw then
          fs.write(autoload_root .. "/" .. entry, raw)
        end
      end
    end
  end
  fs.write(opts.target .. "/liv.lock", lockfile.serialize(lock))

  return { modules = closure.modules, external = closure.external, lock = lock }
end

return M
