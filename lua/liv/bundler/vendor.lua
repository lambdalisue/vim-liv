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

  local closure = analyze.closure(opts.roots, resolver.read)
  local vendored = rewrite.name_set(closure.modules)

  fs.clean(vendor_root) -- clean reinstall: never leave a stale vendored module

  local lock = { modules = {} }
  for _, name in ipairs(closure.modules) do
    local content = resolver.read(name)
    local rewritten = rewrite.rewrite(content, vendored, prefix)
    fs.write(vendor_root .. "/" .. resolver.locate(name), rewritten)
    lock.modules[name] = {
      source = opts.source or "path",
      version = opts.version,
      hash = lockfile.hash(content),
    }
  end
  fs.write(opts.target .. "/liv.lock", lockfile.serialize(lock))

  return { modules = closure.modules, external = closure.external, lock = lock }
end

return M
