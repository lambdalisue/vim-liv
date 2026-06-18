-- liv.bundler.cli — the bundler's canonical entry (spec 0009). bin/liv-bundler
-- (terminal) and :LivBundle (plugin/liv.vim) are thin shims over this. Editor-
-- independent: the &runtimepath read happens in the :LivBundle shim and the string
-- is passed in, so this module never touches the editor.
local vendor = require("liv.bundler.vendor")
local path = require("liv.bundler.source.path")
local rtp = require("liv.bundler.source.rtp")
local iofs = require("liv.bundler._iofs")

local M = {}

-- Parse an argv list. Positional args are module roots; `--key=value` are flags.
---@param argv string[]
---@return { roots: string[], source?: string, from?: string, to?: string, plugin?: string, runtimepath?: string }
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

local function source_kind(opts)
  return opts.source or (opts.runtimepath and "rtp") or "path"
end

-- Run a bundle. opts from parse(); env (optional) injects { fs, resolver } for tests.
---@param opts table
---@param env? { fs?: table, resolver?: table }
---@return { modules: string[], external: string[], lock: table }
function M.main(opts, env)
  env = env or {}
  local fs = env.fs or iofs
  assert(opts.roots and #opts.roots > 0, "liv.bundler: no modules to bundle")
  assert(opts.plugin and opts.plugin ~= "", "liv.bundler: --plugin=<name> is required")

  local resolver = env.resolver
  if not resolver then
    local kind = source_kind(opts)
    if kind == "rtp" then
      assert(opts.runtimepath, "liv.bundler: rtp source needs a runtimepath (run from the editor)")
      resolver = rtp.resolver(rtp.lua_roots(opts.runtimepath), fs)
    elseif kind == "path" then
      assert(opts.from, "liv.bundler: path source needs --from=<dir>")
      resolver = path.resolver(opts.from, fs)
    else
      error("liv.bundler: unknown source '" .. kind .. "'")
    end
  end

  return vendor.vendor({
    roots = opts.roots,
    resolver = resolver,
    fs = fs,
    target = opts.to or ".",
    plugin = opts.plugin,
    source = source_kind(opts),
  })
end

-- Editor entry for :LivBundle. The shim passes the raw args string and the current
-- &runtimepath; this splits, bundles (rtp source by default), and prints a summary.
---@param argstr string
---@param runtimepath string
---@return table result
function M._command(argstr, runtimepath)
  local argv = {}
  for word in argstr:gmatch("%S+") do
    argv[#argv + 1] = word
  end
  local opts = M.parse(argv)
  opts.source = opts.source or "rtp"
  opts.runtimepath = opts.runtimepath or runtimepath
  local res = M.main(opts)
  print(string.format("liv: vendored %d modules into %s", #res.modules, opts.to or "."))
  if #res.external > 0 then
    print("liv: external (not vendored): " .. table.concat(res.external, ", "))
  end
  return res
end

return M
