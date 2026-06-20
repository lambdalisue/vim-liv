-- liv.tester.cli — one command to run a liv plugin's specs, so neither liv nor a
-- plugin author writes per-project runner boilerplate.
--
-- It runs two layers by directory convention under the project root:
--   spec/  -> L1: editor-free, executed in-process under the host interpreter.
--   test/  -> L3: executed inside real Vim (+lua) AND Neovim (headless).
-- Results are aggregated; main() returns the total failure count (the bin shim
-- turns that into an exit code). Dev-only, never vendored (like liv.bundler).

local M = {}

local function succeeded(ret)
  return ret == true or ret == 0
end

local function discover(dir)
  local files = {}
  local p = io.popen("find '" .. dir .. "' -name '*_spec.lua' 2>/dev/null | sort")
  if p then
    for line in p:lines() do
      files[#files + 1] = line
    end
    p:close()
  end
  return files
end

-- Load + run L1 specs in-process. Returns passed, failed, failures.
local function run_l1(files, tester)
  tester.reset()
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
  for _, lf in ipairs(load_failures) do
    failed = failed + 1
    failures[#failures + 1] = lf
  end
  return passed, failed, failures
end

-- Run L3 specs inside one editor (separate process). Returns passed, failed, and
-- the raw result body (for echoing failure detail).
local function run_l3_editor(bin, files, root, project)
  local list = os.tmpname()
  local lf = assert(io.open(list, "w"))
  for _, x in ipairs(files) do
    lf:write(x, "\n")
  end
  lf:close()
  local out = os.tmpname()
  local entry = root .. "/lua/liv/tester/_editor.lua"
  local invoke
  if bin == "nvim" then
    invoke = string.format('nvim --headless --clean -c "luafile %s" -c "qa!"', entry)
  else
    invoke = string.format('vim -es --clean -c "lua dofile(\'%s\')" -c "qa!"', entry)
  end
  local env = string.format(
    "LIV_ROOT='%s' LIV_PROJECT='%s' LIV_L3_LIST='%s' LIV_L3_OUT='%s' ",
    root,
    project,
    list,
    out
  )
  os.execute(env .. invoke .. " >/dev/null 2>&1")

  local fh = io.open(out, "r")
  if not fh then
    return 0, 1, "FAIL\t" .. bin .. " [no result file]\n"
  end
  local body = fh:read("*a")
  fh:close()
  local p, f = body:match("RESULT\t(%d+)\t(%d+)")
  return tonumber(p) or 0, tonumber(f) or 1, body
end

local function print_detail(body)
  for line in (body or ""):gmatch("[^\n]+") do
    if not line:match("^RESULT") then
      io.write("  " .. line .. "\n")
    end
  end
end

-- opts.root    = vim-liv root (so liv.tester resolves in spawned editors)
-- opts.project = plugin-under-test root (its spec/ and test/, and its lua/)
function M.main(opts)
  opts = opts or {}
  local root = opts.root or "."
  local project = opts.project or "."
  local tester = require("liv.tester")
  tester.install()

  local total_fail, ran_any = 0, false

  local l1 = discover(project .. "/spec")
  if #l1 > 0 then
    ran_any = true
    local p, f, failures = run_l1(l1, tester)
    total_fail = total_fail + f
    io.write(string.format("L1 (no editor): %d passed, %d failed\n", p, f))
    for _, x in ipairs(failures) do
      io.write("  FAIL " .. x.name .. "\n")
      io.write("    " .. tostring(x.err):gsub("\n", "\n    ") .. "\n")
    end
  end

  local l3 = discover(project .. "/test")
  if #l3 > 0 then
    -- LIV_L3_EDITORS (comma-separated) overrides the default both-editor run, so a
    -- caller can target a single editor (e.g. `just test:vim` / `just test:nvim`).
    local editors = { "nvim", "vim" }
    local only = os.getenv("LIV_L3_EDITORS")
    if only and only ~= "" then
      editors = {}
      for name in only:gmatch("[^,%s]+") do
        editors[#editors + 1] = name
      end
    end
    for _, bin in ipairs(editors) do
      if succeeded(os.execute("command -v " .. bin .. " >/dev/null 2>&1")) then
        ran_any = true
        local p, f, body = run_l3_editor(bin, l3, root, project)
        total_fail = total_fail + f
        io.write(string.format("L3 %-5s: %d passed, %d failed\n", bin, p, f))
        print_detail(body)
      else
        io.write("L3 " .. bin .. " : SKIP (not found)\n")
      end
    end
  end

  if not ran_any then
    io.write("no specs found (expected spec/ for L1 and/or test/ for L3)\n")
  end
  io.write(string.format("\nTOTAL: %d failed\n", total_fail))
  return total_fail
end

return M
