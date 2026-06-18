-- liv.bundler.cli — the bundler's canonical entry (spec 0009). bin/liv-bundler
-- (terminal) and the :Liv* commands (plugin/liv.vim) are thin shims over this.
-- Editor-independent: the &runtimepath read happens in the :Liv* shim and the
-- string is passed in, so this module never touches the editor.
--
-- Commands: bundle (vendor roots, or rebuild from the lockfile when none given),
-- check (drift / missing vs the lockfile), remove (drop roots + now-unused deps),
-- update (re-vendor + migration notices).
local vendor = require("liv.bundler.vendor")
local lockfile = require("liv.bundler.lockfile")
local migrate = require("liv.bundler.migrate")
local path = require("liv.bundler.source.path")
local rtp = require("liv.bundler.source.rtp")
local git = require("liv.bundler.source.git")
local iofs = require("liv.bundler._iofs")

local M = {}

-- Parse an argv list. Positional args are module roots; `--key=value` are flags.
---@param argv string[]
---@return table opts
function M.parse(argv)
  local opts = { roots = {} }
  for _, a in ipairs(argv) do
    local k, v = a:match("^%-%-([%w_]+)=(.*)$")
    if k then
      opts[k] = v
    else
      opts.roots[#opts.roots + 1] = a
    end
  end
  return opts
end

local function source_kind(spec)
  return spec.source or (spec.runtimepath and "rtp") or "path"
end

-- Build a source resolver from a spec { source, from, ref, runtimepath, exec }.
local function build_resolver(spec, fs)
  local kind = source_kind(spec)
  if kind == "rtp" then
    assert(spec.runtimepath, "liv.bundler: rtp source needs a runtimepath (run from the editor)")
    return rtp.resolver(rtp.lua_roots(spec.runtimepath), fs)
  elseif kind == "path" then
    assert(spec.from, "liv.bundler: path source needs --from=<dir>")
    return path.resolver(spec.from, fs)
  elseif kind == "git" then
    assert(spec.from, "liv.bundler: git source needs --from=<url>")
    local dest = spec.gitdest or (os.tmpname() .. ".gitsrc")
    return git.resolver(spec.from, spec.ref, dest, fs, spec.exec or iofs.exec)
  end
  error("liv.bundler: unknown source '" .. kind .. "'")
end

local function read_lock(fs, target)
  local text = fs.read(target .. "/liv.lock")
  return text and lockfile.parse(text) or nil
end

local function vendor_root_of(target, plugin)
  return target .. "/lua/" .. (plugin:gsub("%.", "/")) .. "/vendor"
end

-- Run a bundle. With no roots, rebuild from the lockfile (meta) at --to. env
-- (optional) injects { fs, resolver } for tests.
---@param opts table
---@param env? { fs?: table, resolver?: table }
---@return { modules: string[], external: string[], lock: table }
function M.main(opts, env)
  env = env or {}
  local fs = env.fs or iofs
  local target = opts.to or "."

  if not opts.roots or #opts.roots == 0 then
    local lock = read_lock(fs, target)
    if lock then
      opts.roots = lock.meta.roots or {}
      opts.plugin = opts.plugin or lock.meta.plugin
      opts.source = opts.source or lock.meta.source
      opts.from = opts.from or lock.meta.from
      opts.ref = opts.ref or lock.meta.ref
    end
  end
  assert(opts.roots and #opts.roots > 0, "liv.bundler: no modules to bundle")
  assert(opts.plugin and opts.plugin ~= "", "liv.bundler: --plugin=<name> is required")

  local resolver = env.resolver or build_resolver(opts, fs)
  return vendor.vendor({
    roots = opts.roots,
    resolver = resolver,
    fs = fs,
    target = target,
    plugin = opts.plugin,
    source = source_kind(opts),
    from = opts.from,
    ref = opts.ref,
  })
end

-- Add modules to the bundle: vendor the UNION of the given roots with the roots
-- already recorded in the lockfile (so re-running adds rather than replaces), then
-- re-vendor that union. The first add (no lockfile) is just the given roots; it
-- inherits plugin/source/from from the lockfile when present.
---@param opts table
---@param env? table
function M.add(opts, env)
  env = env or {}
  local fs = env.fs or iofs
  local target = opts.to or "."
  local lock = read_lock(fs, target)
  local meta = lock and lock.meta or {}

  local roots, seen = {}, {}
  for _, r in ipairs(meta.roots or {}) do
    if not seen[r] then
      seen[r], roots[#roots + 1] = true, r
    end
  end
  for _, r in ipairs(opts.roots or {}) do
    if not seen[r] then
      seen[r], roots[#roots + 1] = true, r
    end
  end

  return M.main({
    roots = roots,
    plugin = opts.plugin or meta.plugin,
    source = opts.source or meta.source,
    from = opts.from or meta.from,
    ref = opts.ref or meta.ref,
    to = target,
    runtimepath = opts.runtimepath,
  }, env)
end

-- Read-only: report modules whose source drifted from the lockfile hash, and
-- modules recorded in the lockfile but missing from the vendor tree.
---@param opts table
---@param env? { fs?: table, resolver?: table }
---@return { drifted: string[], missing: string[], ok: boolean }
function M.check(opts, env)
  env = env or {}
  local fs = env.fs or iofs
  local target = opts.to or "."
  local lock = assert(read_lock(fs, target), "liv.bundler: no lockfile at " .. target)
  local resolver = env.resolver
    or build_resolver({
      source = lock.meta.source,
      from = opts.from or lock.meta.from,
      ref = lock.meta.ref,
      runtimepath = opts.runtimepath,
      exec = opts.exec,
    }, fs)
  local vroot = vendor_root_of(target, lock.meta.plugin or "_")
  local drifted, missing = {}, {}
  for name, rec in pairs(lock.modules) do
    local cur = resolver.read(name)
    if cur and lockfile.hash(cur) ~= rec.hash then
      drifted[#drifted + 1] = name
    end
    local rel = resolver.locate(name)
    if not (rel and fs.read(vroot .. "/" .. rel)) then
      missing[#missing + 1] = name
    end
  end
  table.sort(drifted)
  table.sort(missing)
  return { drifted = drifted, missing = missing, ok = #drifted == 0 and #missing == 0 }
end

-- Remove the given roots (and any deps no longer needed) by re-vendoring with the
-- remaining roots. Removing every root cleans the vendor tree and empties the lock.
---@param opts table
---@param env? table
function M.remove(opts, env)
  env = env or {}
  local fs = env.fs or iofs
  local target = opts.to or "."
  local lock = assert(read_lock(fs, target), "liv.bundler: no lockfile at " .. target)
  local removing = {}
  for _, r in ipairs(opts.roots) do
    removing[r] = true
  end
  local remaining = {}
  for _, r in ipairs(lock.meta.roots or {}) do
    if not removing[r] then
      remaining[#remaining + 1] = r
    end
  end
  if #remaining == 0 then
    fs.clean(vendor_root_of(target, lock.meta.plugin))
    local empty = { meta = { plugin = lock.meta.plugin, source = lock.meta.source, from = lock.meta.from, roots = {} }, modules = {} }
    fs.write(target .. "/liv.lock", lockfile.serialize(empty))
    return { modules = {}, external = {}, lock = empty }
  end
  return M.main({
    roots = remaining,
    plugin = lock.meta.plugin,
    source = lock.meta.source,
    from = opts.from or lock.meta.from,
    ref = lock.meta.ref,
    to = target,
    runtimepath = opts.runtimepath,
  }, env)
end

-- Re-vendor from the lockfile (or given roots) to the current source. When the
-- caller supplies migrations text and from/to versions, return the migration
-- notices that affect bundled modules (the version inference for git tags is a
-- later refinement; for path/rtp there are no versions, so no notices).
---@param opts table
---@param env? table
---@return table result with a `.notices` list
function M.update(opts, env)
  env = env or {}
  local fs = env.fs or iofs
  local target = opts.to or "."
  local lock = assert(read_lock(fs, target), "liv.bundler: no lockfile at " .. target)
  local roots = (opts.roots and #opts.roots > 0) and opts.roots or lock.meta.roots

  local notices = {}
  if opts.migrations and opts.from_version and opts.to_version then
    local bundled = {}
    for n in pairs(lock.modules) do
      bundled[n] = true
    end
    notices = migrate.relevant(migrate.parse(opts.migrations), opts.from_version, opts.to_version, bundled)
  end

  local res = M.main({
    roots = roots,
    plugin = lock.meta.plugin,
    source = lock.meta.source,
    from = opts.from or lock.meta.from,
    ref = opts.ref or lock.meta.ref,
    to = target,
    runtimepath = opts.runtimepath,
  }, env)
  res.notices = notices
  return res
end

-- Editor entry for the :Liv* commands. The shim passes the command name, the raw
-- args string, and the current &runtimepath; this splits, runs, and prints.
---@param command string "add" | "check" | "remove" | "update"
---@param argstr string
---@param runtimepath string
---@return table result
function M._command(command, argstr, runtimepath)
  local argv = {}
  for word in argstr:gmatch("%S+") do
    argv[#argv + 1] = word
  end
  local opts = M.parse(argv)
  opts.runtimepath = opts.runtimepath or runtimepath
  if not opts.source then
    opts.source = "rtp"
  end

  if command == "check" then
    local r = M.check(opts)
    if r.ok then
      print("liv: vendor tree is up to date with the lockfile")
    else
      if #r.drifted > 0 then
        print("liv: drifted from source: " .. table.concat(r.drifted, ", "))
      end
      if #r.missing > 0 then
        print("liv: missing from vendor tree: " .. table.concat(r.missing, ", "))
      end
    end
    return r
  end

  local res
  if command == "remove" then
    res = M.remove(opts)
  elseif command == "update" then
    res = M.update(opts)
  else -- "add"
    res = M.add(opts)
  end
  print(string.format("liv: vendored %d modules into %s", #res.modules, opts.to or "."))
  for _, n in ipairs(res.notices or {}) do
    print("liv: migration " .. n.version .. " — " .. n.description)
  end
  if #res.external > 0 then
    print("liv: external (not vendored): " .. table.concat(res.external, ", "))
  end
  return res
end

return M
