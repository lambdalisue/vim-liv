-- liv.tester._l3 — the L3 orchestrator: per-file process isolation for the
-- editor-bound test layer, and the robustness that buys.
--
-- liv's reason to exist is one Lua source on BOTH Vim (+lua) and Neovim; the L3
-- layer is where that promise is verified, so its runner must be the sturdiest
-- part of the tester. Running every `test/` file in ONE editor process per editor
-- means a single spec that crashes or hangs takes ALL L3 results down with it.
-- This module runs each (file, editor) cell in its OWN editor invocation and
-- aggregates, so one bad cell costs one cell:
--   * a child that crashes (writes no/partial result file) is a FAILURE naming
--     the file+editor — never silently lost;
--   * a child that hangs is SIGTERM-killed at a per-file timeout — also a failure;
--   * `--jobs N` runs up to N children at once (background spawn + result-file
--     poll), aggregated deterministically in file × editor order regardless of
--     completion order;
--   * `--fail-fast` / `--max-failures N` stop launching new cells once the
--     failure budget is spent; the un-launched cells are reported skipped.
--
-- The child command is INJECTED (`opts.build_command`) so the spawn/poll/kill
-- machinery is L1-testable against fake child commands (shell one-liners) without
-- a real editor. The default builder reuses the existing `_editor.lua` env +
-- result-file protocol, one list-file entry per child, so `_editor.lua` is
-- unchanged.

local M = {}

-- Default per-file timeout (seconds). Generous on purpose: a real editor cold
-- start can take a few seconds, and a false timeout would turn a healthy run red.
-- L1 tests pass a tiny timeout to their fake children to keep the suite fast.
local DEFAULT_TIMEOUT = 60

-- Poll interval (seconds) while waiting on in-flight children. Small enough to
-- keep latency low, large enough not to busy-spin.
local POLL_INTERVAL = 0.05

local function shquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- The default child-command builder: launch one editor on a single `file` with
-- the existing env + result-file protocol (`_editor.lua` reads a one-entry list
-- file and writes RESULT to `out`). Selection is propagated via LIV_SELECT; the
-- run order seed via LIV_SEED; the `--failed` exact-name set via LIV_FAILED — so
-- the same filtering/ordering applies identically inside the child editor.
---@param root string vim-liv root (so liv.tester resolves in the child)
---@param project string plugin-under-test root
---@param selectors string[] newline-joined into LIV_SELECT
---@param extra? { seed?: integer, failed_names?: string[] } LIV_SEED / LIV_FAILED
---@return fun(file: string, editor: string, out: string): string
function M.default_build_command(root, project, selectors, extra)
  extra = extra or {}
  local entry = root .. "/lua/liv/tester/_editor.lua"
  return function(file, editor, out)
    -- One temp list file per child holds exactly this file (per-file isolation).
    local list = os.tmpname()
    local lf = assert(io.open(list, "w"))
    lf:write(file, "\n")
    lf:close()

    local invoke
    if editor == "nvim" then
      invoke = string.format('nvim --headless --clean -c "luafile %s" -c "qa!"', entry)
    else
      invoke = string.format('vim -es --clean -c "lua dofile(\'%s\')" -c "qa!"', entry)
    end

    local env = string.format(
      "LIV_ROOT=%s LIV_PROJECT=%s LIV_L3_LIST=%s LIV_L3_OUT=%s ",
      shquote(root),
      shquote(project),
      shquote(list),
      shquote(out)
    )
    if selectors and #selectors > 0 then
      env = env .. "LIV_SELECT=" .. shquote(table.concat(selectors, "\n")) .. " "
    end
    if extra.seed ~= nil then
      env = env .. "LIV_SEED=" .. shquote(tostring(extra.seed)) .. " "
    end
    if extra.failed_names and #extra.failed_names > 0 then
      env = env .. "LIV_FAILED=" .. shquote(table.concat(extra.failed_names, "\n")) .. " "
    end
    return env .. invoke .. " >/dev/null 2>&1"
  end
end

-- Launch `command` detached in the background and return its PID (a number) or
-- nil on failure. The child's stdout/stderr are the caller's responsibility
-- (the default builder already redirects them); here we only capture the PID.
--
-- The command is wrapped in a subshell `( … )` BEFORE `&`: in `/bin/sh`, `&`
-- binds only to the last statement of a `a; b; c` sequence, so without the
-- subshell a multi-statement command would background only its tail and block
-- popen on the rest — silently serializing parallel children. `$!` then is the
-- subshell's PID, which we poll/kill as the whole child.
local function spawn(command)
  local p = io.popen("( " .. command .. " ) & echo $!")
  if not p then
    return nil
  end
  local pid = p:read("*l")
  p:close()
  return tonumber(pid)
end

local function alive(pid)
  return os.execute("kill -0 " .. pid .. " 2>/dev/null") == 0
    or os.execute("kill -0 " .. pid .. " 2>/dev/null") == true
end

local function term(pid)
  os.execute("kill -TERM " .. pid .. " 2>/dev/null")
end

local function sleep(seconds)
  os.execute("sleep " .. tostring(seconds))
end

-- Read and parse a child's result file AFTER it has exited. A present, parseable
-- RESULT line yields passed/failed/skipped + the raw body; a missing or partial
-- file is a single failure (the child crashed before writing a usable result).
---@return { passed: integer, failed: integer, skipped: integer, detail: string, ok: boolean }
local function collect_result(out, file, editor)
  local fh = io.open(out, "r")
  if not fh then
    return {
      passed = 0,
      failed = 1,
      skipped = 0,
      ok = false,
      detail = "FAIL\t" .. file .. " (" .. editor .. ") [no result file: child crashed]",
    }
  end
  local body = fh:read("*a")
  fh:close()
  local p, f, s = body:match("RESULT\t(%d+)\t(%d+)\t(%d+)")
  if not p then
    return {
      passed = 0,
      failed = 1,
      skipped = 0,
      ok = false,
      detail = "FAIL\t" .. file .. " (" .. editor .. ") [partial result file: child crashed]",
    }
  end
  return {
    passed = tonumber(p),
    failed = tonumber(f),
    skipped = tonumber(s),
    ok = true,
    detail = body,
  }
end

-- Build the ordered list of cells to run: file × editor, files in given order,
-- editors in given order (so aggregation is deterministic).
local function build_cells(files, editors)
  local cells = {}
  for _, file in ipairs(files) do
    for _, editor in ipairs(editors) do
      cells[#cells + 1] = { file = file, editor = editor }
    end
  end
  return cells
end

-- Run the L3 cells with per-file process isolation, a per-file timeout, up to
-- `jobs` children in parallel, and fail-fast/max-failures budgets.
--
-- opts:
--   files          string[]  spec file paths (each runs in its own child)
--   editors        string[]  editor names in run order (e.g. {"nvim","vim"})
--   jobs           integer   max concurrent children (default 1, sequential)
--   timeout        number    per-file timeout in seconds (default 60)
--   fail_fast      boolean   stop launching after the first failure
--   max_failures   integer?  stop launching after this many failures
--   build_command  fun(file, editor, out): string  child command (injected)
--
-- Returns an outcome:
--   { results = Cell[], passed, failed, skipped }
-- where each Cell is { file, editor, passed, failed, skipped, detail, status }
-- and `status` is "ran" | "failed" (crash/timeout) | "skipped" (not launched).
-- Results are ordered by file × editor regardless of completion order.
---@param opts table
---@return table outcome
function M.run(opts)
  local files = opts.files or {}
  local editors = opts.editors or { "nvim", "vim" }
  local jobs = opts.jobs or 1
  if jobs < 1 then
    jobs = 1
  end
  local timeout = opts.timeout or DEFAULT_TIMEOUT
  local build_command = assert(opts.build_command, "build_command is required")
  local fail_fast = opts.fail_fast or false
  local max_failures = opts.max_failures
  if fail_fast then
    max_failures = math.min(max_failures or 1, 1)
  end

  local cells = build_cells(files, editors)
  local results = {} -- keyed by cell index, filled deterministically below

  local total_failed = 0
  local function budget_spent()
    return max_failures ~= nil and total_failed >= max_failures
  end

  local launched = {} -- index -> true once a cell has been launched/resolved
  local running = {} -- index -> { cell, pid, out, deadline }
  local inflight_files = {} -- file -> true while a child for it is running

  -- Drain finished children; returns nothing but mutates `results`/`running`.
  local function reap(block)
    while next(running) ~= nil do
      local progressed = false
      for index, job in pairs(running) do
        if not alive(job.pid) then
          -- Child exited: read its result post-exit (avoids partial-file races).
          local r = collect_result(job.out, job.cell.file, job.cell.editor)
          os.remove(job.out)
          results[index] = {
            file = job.cell.file,
            editor = job.cell.editor,
            passed = r.passed,
            failed = r.failed,
            skipped = r.skipped,
            detail = r.detail,
            status = "ran",
          }
          total_failed = total_failed + r.failed
          running[index] = nil
          inflight_files[job.cell.file] = nil
          progressed = true
        elseif os.time() >= job.deadline then
          -- Hung child: SIGTERM it and record a timeout failure.
          term(job.pid)
          sleep(0.1)
          term(job.pid)
          os.remove(job.out)
          results[index] = {
            file = job.cell.file,
            editor = job.cell.editor,
            passed = 0,
            failed = 1,
            skipped = 0,
            detail = "FAIL\t"
              .. job.cell.file
              .. " ("
              .. job.cell.editor
              .. ") [timeout: child killed after "
              .. tostring(timeout)
              .. "s]",
            status = "failed",
          }
          total_failed = total_failed + 1
          running[index] = nil
          inflight_files[job.cell.file] = nil
          progressed = true
        end
      end
      if not block then
        return
      end
      if not progressed then
        sleep(POLL_INTERVAL)
      end
      -- When blocking, only need to free one slot; return once any progressed.
      if progressed then
        return
      end
    end
  end

  local running_count = 0

  -- Find the next launchable cell: the lowest-index cell not yet launched whose
  -- file is not currently in-flight. The same file never runs on two editors at
  -- once (a file's external side effects — e.g. a shared temp dir — are per-file
  -- global, so its cells must serialize), while DIFFERENT files run in parallel.
  -- Cells are interleaved as file × editor, so scanning ahead past an in-flight
  -- file still fills all `jobs` slots (it does not throttle to ~2).
  local function next_launchable()
    for index = 1, #cells do
      if not launched[index] and not inflight_files[cells[index].file] then
        return index
      end
    end
    return nil
  end

  local function any_unlaunched()
    for index = 1, #cells do
      if not launched[index] then
        return true
      end
    end
    return false
  end

  while any_unlaunched() or next(running) ~= nil do
    -- Launch while there is capacity, a launchable cell, and budget left.
    while running_count < jobs and not budget_spent() do
      local index = next_launchable()
      if not index then
        break
      end
      launched[index] = true
      local cell = cells[index]
      local out = os.tmpname()
      os.remove(out) -- ensure absence until the child writes it
      local command = build_command(cell.file, cell.editor, out)
      local pid = spawn(command)
      if not pid then
        results[index] = {
          file = cell.file,
          editor = cell.editor,
          passed = 0,
          failed = 1,
          skipped = 0,
          detail = "FAIL\t" .. cell.file .. " (" .. cell.editor .. ") [could not spawn child]",
          status = "failed",
        }
        total_failed = total_failed + 1
      else
        running[index] = {
          cell = cell,
          pid = pid,
          out = out,
          deadline = os.time() + timeout,
        }
        inflight_files[cell.file] = true
        running_count = running_count + 1
      end
    end

    if next(running) ~= nil then
      local before = 0
      for _ in pairs(running) do
        before = before + 1
      end
      reap(true)
      local after = 0
      for _ in pairs(running) do
        after = after + 1
      end
      running_count = running_count - (before - after)
    elseif budget_spent() then
      break
    elseif not any_unlaunched() then
      break
    end
  end

  -- Any cell never launched (budget spent) is reported as skipped.
  for index = 1, #cells do
    if results[index] == nil then
      local cell = cells[index]
      results[index] = {
        file = cell.file,
        editor = cell.editor,
        passed = 0,
        failed = 0,
        skipped = 0,
        detail = "SKIP\t"
          .. cell.file
          .. " ("
          .. cell.editor
          .. ") [not run: failure budget spent]",
        status = "skipped",
      }
    end
  end

  -- Aggregate in deterministic cell order.
  local passed, failed, skipped = 0, 0, 0
  local ordered = {}
  for index = 1, #cells do
    local r = results[index]
    ordered[#ordered + 1] = r
    passed = passed + r.passed
    failed = failed + r.failed
    -- A not-launched cell contributes one skipped unit (the whole file), so the
    -- run advertises that work was deliberately skipped, not silently dropped.
    if r.status == "skipped" then
      skipped = skipped + 1
    else
      skipped = skipped + r.skipped
    end
  end

  return {
    results = ordered,
    passed = passed,
    failed = failed,
    skipped = skipped,
  }
end

return M
