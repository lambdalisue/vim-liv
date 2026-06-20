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
--   LIV_SELECT     (optional) newline-separated selectors; applied identically
--                  to L1 so an in-editor run filters the same way
--   LIV_SEED       (optional) integer; randomize test order reproducibly
--   LIV_FAILED     (optional) newline-separated EXACT full titles; `--failed`
--                  rerun restricts to exactly these (ANDed with LIV_SELECT)
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
local select = require("liv.tester._select")
tester.install()

local selectors = {}
do
  local raw = os.getenv("LIV_SELECT")
  if raw and raw ~= "" then
    for sel in raw:gmatch("[^\n]+") do
      selectors[#selectors + 1] = sel
    end
  end
end
local select_filter = select.compile(selectors)

-- `--failed` rerun: an EXACT full-title set membership filter (NOT the Lua-
-- pattern select path), ANDed with the selector filter so a child reruns exactly
-- the previously-failing tests that also satisfy any active selector.
local filter = select_filter
do
  local raw = os.getenv("LIV_FAILED")
  if raw and raw ~= "" then
    local names = {}
    for name in raw:gmatch("[^\n]+") do
      names[#names + 1] = name
    end
    local failed_filter = require("liv.tester._failed").filter(names)
    filter = function(title, tags)
      return failed_filter(title, tags) and select_filter(title, tags)
    end
  end
end

local seed = tonumber(os.getenv("LIV_SEED"))

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

local passed, failed, skipped, failures = tester.run(nil, { filter = filter, seed = seed })
for _, f in ipairs(load_failures) do
  failed = failed + 1
  failures[#failures + 1] = f
end

local out = assert(io.open(os.getenv("LIV_L3_OUT"), "w"))
out:write(string.format("RESULT\t%d\t%d\t%d\n", passed, failed, skipped))
for _, f in ipairs(failures) do
  out:write("FAIL\t" .. f.name .. "\n")
  out:write("  " .. tostring(f.err):gsub("\n", "\n  ") .. "\n")
end
out:close()
