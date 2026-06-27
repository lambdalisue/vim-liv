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

-- Put the vim-liv root and the plugin-under-test root on &runtimepath so the
-- editor auto-sources their autoload/ companions (e.g. liv#std#process#Start) the
-- same way an installed plugin would. package.path covers Lua `require`; autoload
-- functions are resolved via runtimepath, and `--clean` reset it to defaults.
do
  local nvim = vim.api ~= nil
  for _, p in ipairs({ root, project }) do
    local cmd = "set runtimepath^=" .. vim.fn.fnameescape(p)
    if nvim then
      vim.api.nvim_command(cmd)
    else
      vim.command(cmd)
    end
  end
end

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

-- Run WITH a capturing reporter so each test's per-test record (name, status,
-- duration, error, file, line) survives out of the editor — the parent replays
-- these through the main reporter so L3 shows per-test detail, not just counts.
local layer = require("liv.tester._layer")
local rec = layer.recorder()
local passed, failed, skipped = tester.run(rec.reporter, { filter = filter, seed = seed })

-- A load/register failure precedes any test event (the spec never built its
-- registry), so the recorder never saw it; synthesize a failed record per one so
-- it is visible and counted — the L3 analog of a crashed cell.
local events = rec.events()
for _, f in ipairs(load_failures) do
  failed = failed + 1
  events[#events + 1] =
    { "test_end", { name = f.name, status = "failed", duration = 0, error = tostring(f.err) } }
end

local out = assert(io.open(os.getenv("LIV_L3_OUT"), "w"))
out:write(string.format("RESULT\t%d\t%d\t%d\n", passed, failed, skipped))
-- The per-test event stream follows an EVENTS marker (a Lua return-table the
-- parent loads); a partial write leaves it unparseable, which the parent reads as
-- a crash. The RESULT line above stays as the back-compatible summary + crash gate.
out:write("EVENTS\n")
out:write(layer.serialize(events))
out:close()
