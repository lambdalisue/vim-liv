-- liv.tester in-editor entry: loaded INSIDE Vim (+lua) / Neovim by the CLI to
-- run a spec list and write results to a file. Not a public API — invoked via
-- `:luafile` / `dofile` by liv.tester.cli. (Inside `vim -es`, `print` is
-- swallowed, so results go to a file the launcher reads.)
--
-- Environment inputs (the editor entry takes no argv):
--   LIV_ROOT       vim-liv root (so `liv.tester` resolves)
--   LIV_PROJECT    the plugin-under-test root (so its own lua/ modules resolve)
--   LIV_L3_LIST    path to a file of newline-separated absolute spec paths
--   LIV_L3_OUT     path to write results to
local root = os.getenv("LIV_ROOT") or "."
local project = os.getenv("LIV_PROJECT") or "."
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  project .. "/lua/?.lua",
  project .. "/lua/?/init.lua",
  package.path,
}, ";")

local tester = require("liv.tester")
tester.install()

local files = {}
do
  local list = io.open(os.getenv("LIV_L3_LIST") or "", "r")
  if list then
    for f in list:lines() do
      if f ~= "" then
        files[#files + 1] = f
      end
    end
    list:close()
  end
end

local load_failures = {}
for _, file in ipairs(files) do
  local chunk, err = loadfile(file)
  if not chunk then
    load_failures[#load_failures + 1] = { name = file .. " [load]", err = tostring(err) }
  else
    local ok, rerr = xpcall(chunk, function(e)
      return debug.traceback(tostring(e), 2)
    end)
    if not ok then
      load_failures[#load_failures + 1] = { name = file .. " [register]", err = rerr }
    end
  end
end

local passed, failed, failures = tester.run()
for _, f in ipairs(load_failures) do
  failed = failed + 1
  failures[#failures + 1] = f
end

local out = assert(io.open(os.getenv("LIV_L3_OUT"), "w"))
out:write(string.format("RESULT\t%d\t%d\n", passed, failed))
for _, f in ipairs(failures) do
  out:write("FAIL\t" .. f.name .. "\n")
  out:write("  " .. tostring(f.err):gsub("\n", "\n  ") .. "\n")
end
out:close()
