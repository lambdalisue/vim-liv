-- liv.tester.cli — one command to run a liv plugin's specs, so neither liv nor a
-- plugin author writes per-project runner boilerplate.
--
-- It runs two layers by directory convention under the project root:
--   spec/  -> L1: editor-free, executed in-process under the host interpreter.
--   test/  -> L3: executed inside real Vim (+lua) AND Neovim (headless).
-- Results are aggregated; main() returns a structured exit code (0 ok / 1 test
-- failures / 2 usage error / 4 no tests found) that the bin shim passes straight
-- to os.exit. Dev-only, never vendored (like liv.bundler).

local argument = require("liv.lua.argument.parse")
local select = require("liv.tester._select")
local l3runner = require("liv.tester._l3")
local reporters = require("liv.tester.reporters")
local config = require("liv.tester._config")
local failed_store = require("liv.tester._failed")

local M = {}

local function succeeded(ret)
  return ret == true or ret == 0
end

-- Is stdout a terminal? `os.execute("test -t 1")` runs in a subshell that
-- inherits the CLI's fd 1, so this reflects whether OUR stdout is a tty — the
-- signal for the default reporter (spec) and for color.
local function stdout_is_tty()
  return succeeded(os.execute("test -t 1"))
end

-- The default reporter when `--reporter` is absent: the human `spec` reporter on
-- an interactive terminal, else `tap` (the CI lingua franca) so piped/redirected
-- output is machine-parseable by default.
---@param is_tty boolean
---@return string
function M.default_reporter(is_tty)
  if is_tty then
    return "spec"
  end
  return "tap"
end

local VERSION = "0.1.0"

local USAGE = [[
liv-tester — run liv plugin specs on Vim (+lua) and Neovim.

Usage: liv-tester [init] [PATH...] [options]

  init                 Scaffold a .liv-tester.lua + an example spec, then exit.
  PATH...              Restrict the run to these spec/test files (positional).
  --select=<selector>  Filter tests by selector (repeatable; multiple = OR).
                       Selector terms (comma = AND): name:<pat>, tag:<pat>,
                       a bare word = name:, a leading ! negates. Lua patterns,
                       case-insensitive.
  --reporter=<name>    Output reporter for the L1 detail: spec, tap, jsonl, or
                       junit. Default: spec on a terminal, tap otherwise.
  --verbose            More detail (spec reporter shows passing tests too).
  --quiet              Less detail (spec reporter hides suites/passing tests).
  --jobs=<N>           Run up to N L3 child editors in parallel (default 1).
  --fail-fast          Stop launching new L3 cells after the first failure.
  --max-failures=<N>   Stop launching new L3 cells after N failures.
  --editor=<which>     Which editor(s) run L3: nvim, vim, or both (default both).
  --seed=<N>           Randomize test order reproducibly (echoes the seed). Order
                       is declaration order unless a seed is given.
  --failed             Rerun only the tests that failed in the previous run
                       (exact full-title match; ANDed with --select).
  --list               Print the (filtered) candidate test names without running.
  --watch              Re-run on any change under spec/ test/ lua/ (mtime poll).
  --help               Show this help and exit.
  --version            Show the version and exit.

Settings also come from a .liv-tester.lua (a Lua file returning a table),
discovered by walking up from the project root; precedence is CLI > config >
default. Keys: reporter, select, timeout, jobs, max_failures, fail_fast, editor,
includes, excludes.

Exit codes: 0 all passed, 1 test failures, 2 usage error, 4 no tests found.

The cross-layer roll-up (L1/L3 summary lines + TOTAL) is always printed; the
chosen reporter renders the L1 per-test detail above it.

L3 (test/) runs each file in its OWN editor invocation per editor, so a crash
or hang in one file costs only that cell: a missing result file is reported as
a failure, and a hung child is killed at a per-file timeout.

Values are supplied with `=` (e.g. --select=tag:smoke), per liv's argument
grammar (a `=`-less flag is a boolean and never consumes the next token).
]]

-- Normalize a parsed flag value (scalar, list, or nil) into a list of strings.
local function as_list(value)
  if value == nil then
    return {}
  end
  if type(value) == "table" then
    return value
  end
  return { value }
end

-- Coerce a parsed flag value to a positive integer, falling back to `default`
-- when absent, non-numeric, or below 1. Lets `--jobs=4` parse as the string "4".
local function as_positive_int(value, default)
  local n = tonumber(value)
  if not n or n < 1 then
    return default
  end
  return math.floor(n)
end

-- Resolve the `--editor` choice into an ordered editor list. `both` (the default)
-- runs Neovim then Vim; an explicit `nvim`/`vim` narrows to one.
local function resolve_editors(value)
  if value == "nvim" then
    return { "nvim" }
  end
  if value == "vim" then
    return { "vim" }
  end
  return { "nvim", "vim" }
end

-- Parse CLI argv (a list of tokens) into a settings table. Positionals become
-- `paths`; `--select` collects into `select` (a list); `--reporter` is recorded.
-- `--jobs`/`--fail-fast`/`--max-failures`/`--editor` govern L3 orchestration.
-- Uses liv.lua.argument, so values are supplied with `=` and a `=`-less flag is
-- boolean (never consumes the next token).
---@param argv string[]
---@return { paths: string[], select: string[], reporter?: string, jobs: integer, fail_fast: boolean, max_failures?: integer, editors: string[], help: boolean, version: boolean }
function M.parse_args(argv)
  local _opts, flags, rest = argument.parse(argv or {})
  local reporter = flags.reporter
  local max_failures = tonumber(flags["max-failures"])
  -- `present` records which precedence-governed keys the user EXPLICITLY set, so
  -- config-merge can honor CLI by presence (an absent flag must NOT clobber a
  -- config value). It reads the RAW parsed flags, never the defaulted result.
  local present = {}
  if flags.reporter ~= nil then
    present.reporter = true
  end
  if flags.select ~= nil then
    present.select = true
  end
  if flags.jobs ~= nil then
    present.jobs = true
  end
  if flags.timeout ~= nil then
    present.timeout = true
  end
  if flags["max-failures"] ~= nil then
    present.max_failures = true
  end
  if flags["fail-fast"] ~= nil then
    present.fail_fast = true
  end
  if flags.editor ~= nil then
    present.editor = true
  end
  return {
    paths = rest,
    select = as_list(flags.select),
    reporter = type(reporter) == "string" and reporter or nil,
    jobs = as_positive_int(flags.jobs, 1),
    timeout = tonumber(flags.timeout),
    fail_fast = flags["fail-fast"] == true,
    max_failures = max_failures,
    editors = resolve_editors(flags.editor),
    editor = type(flags.editor) == "string" and flags.editor or nil,
    editor_explicit = type(flags.editor) == "string",
    seed = tonumber(flags.seed),
    failed = flags.failed == true,
    list = flags.list == true,
    watch = flags.watch == true,
    verbose = flags.verbose == true,
    quiet = flags.quiet == true,
    help = flags.help == true,
    version = flags.version == true,
    present = present,
  }
end

-- Build the CLI-overrides table for `_config.merge`: exactly the precedence-
-- governed keys the user EXPLICITLY set (`parsed.present`), and nothing else, so
-- an absent flag stays absent (nil) and cannot clobber a config value. The values
-- are the RAW-typed ones (`select` is a list, `jobs` an integer, `editor` a
-- string) — coercion (`resolve_editors`, `as_positive_int`) happens AFTER merge.
---@param parsed table the result of `parse_args`
---@return table overrides
function M.cli_overrides(parsed)
  local present = parsed.present or {}
  local over = {}
  if present.reporter then
    over.reporter = parsed.reporter
  end
  if present.select then
    over.select = parsed.select
  end
  if present.jobs then
    over.jobs = parsed.jobs
  end
  if present.timeout then
    over.timeout = parsed.timeout
  end
  if present.max_failures then
    over.max_failures = parsed.max_failures
  end
  if present.fail_fast then
    over.fail_fast = parsed.fail_fast
  end
  if present.editor then
    over.editor = parsed.editor
  end
  return over
end

-- Decide the run's process exit code from a flat outcome (spec 0010, Phase 3):
--   2  a usage error (e.g. an unknown --reporter) — checked first;
--   4  no tests were found to run;
--   1  tests ran and at least one failed;
--   0  tests ran and all passed.
-- A pure function so the mapping is L1-testable without driving a real run.
---@param outcome { ran: boolean, failed: integer, usage_error: boolean }
---@return integer
function M.exit_code(outcome)
  if outcome.usage_error then
    return 2
  end
  if not outcome.ran then
    return 4
  end
  if outcome.failed > 0 then
    return 1
  end
  return 0
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

-- Keep only files whose path ends with one of the requested `paths` (so a user
-- can pass `spec/foo_spec.lua` or an absolute path). No paths → keep all.
local function restrict(files, paths)
  if #paths == 0 then
    return files
  end
  local kept = {}
  for _, file in ipairs(files) do
    for _, want in ipairs(paths) do
      if file == want or file:sub(-#want) == want then
        kept[#kept + 1] = file
        break
      end
    end
  end
  return kept
end

-- Load + run L1 specs in-process, driving `reporter` (a run() event table) for
-- the per-test detail. Load/register failures happen BEFORE any test event, so
-- they are returned separately (`load_failures`) for the caller to print and fold
-- into the totals — otherwise a spec that fails to load would be invisible to the
-- reporter and undercount the run. Returns passed, failed, skipped, failures, and
-- load_failures (already included in `failed`/`failures`).
local function run_l1(files, tester, filter, reporter, seed)
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
  local passed, failed, skipped, failures = tester.run(reporter, { filter = filter, seed = seed })
  for _, lf in ipairs(load_failures) do
    failed = failed + 1
    failures[#failures + 1] = lf
  end
  return passed, failed, skipped, failures, load_failures
end

-- Load + register L1 specs into the shared registry WITHOUT running them, for
-- `--list` (which enumerates candidate names via `tester.list`). A spec that
-- fails to load/register is skipped silently here — `--list` is a preview, not a
-- run, so a load error simply omits that file's names rather than failing.
local function run_l1_register_only(files, tester, _filter)
  tester.reset()
  for _, file in ipairs(files) do
    local chunk = loadfile(file)
    if chunk then
      pcall(chunk)
    end
  end
end

-- Echo a child's result body (or a crash/timeout detail line), skipping the
-- machine-readable RESULT header.
local function print_detail(body)
  for line in (body or ""):gmatch("[^\n]+") do
    if not line:match("^RESULT") then
      io.write("  " .. line .. "\n")
    end
  end
end

-- Keep only editors that are actually installed (skip-if-missing), preserving
-- order. Prints a SKIP line for each absent editor.
local function present_editors(editors)
  local present = {}
  for _, bin in ipairs(editors) do
    if succeeded(os.execute("command -v " .. bin .. " >/dev/null 2>&1")) then
      present[#present + 1] = bin
    else
      io.write("L3 " .. bin .. " : SKIP (not found)\n")
    end
  end
  return present
end

-- Resolve the editor set for L3: CLI `--editor` wins; the legacy LIV_L3_EDITORS
-- env stays as a fallback (so existing `just test:vim` / `just test:nvim` keep
-- working); otherwise the parsed default (both). `cli_editors` is what
-- parse_args resolved; `cli_default` is true when the user gave no `--editor`.
local function resolve_l3_editors(cli_editors, cli_default)
  if not cli_default then
    return cli_editors
  end
  local only = os.getenv("LIV_L3_EDITORS")
  if only and only ~= "" then
    local editors = {}
    for name in only:gmatch("[^,%s]+") do
      editors[#editors + 1] = name
    end
    return editors
  end
  return cli_editors
end

local function fmt_layer(label, passed, failed, skipped)
  if skipped > 0 then
    return string.format("%s: %d passed, %d failed, %d skipped\n", label, passed, failed, skipped)
  end
  return string.format("%s: %d passed, %d failed\n", label, passed, failed)
end

-- opts.root    = vim-liv root (so liv.tester resolves in spawned editors)
-- opts.project = plugin-under-test root (its spec/ and test/, and its lua/)
-- opts.argv    = CLI argv tokens (positional paths + --select/--reporter/…)
--
-- Returns a STRUCTURED EXIT CODE (see `exit_code`): 0 all passed, 1 test
-- failures, 2 usage error, 4 no tests found — which `bin/liv-tester` passes
-- straight to `os.exit`.
-- Resolve the effective run settings: parse argv, then merge with a discovered
-- `.liv-tester.lua` under the precedence CLI > config > default, then re-coerce
-- the merged collection keys (editors/jobs/select). The default reporter (TTY ->
-- spec else tap) is left nil here so `main` can apply its TTY-aware default after
-- the merge. Returns the merged settings plus `config_error` (a usage error to
-- surface) and `config_path` (for diagnostics).
local function resolve_settings(project, settings)
  local DEFAULT = {
    reporter = nil, -- decided by TTY in main when unset
    select = nil,
    timeout = nil,
    jobs = 1,
    max_failures = nil,
    fail_fast = false,
    editor = nil, -- nil = both, resolved below
    includes = nil,
    excludes = nil,
  }

  local cfg, config_path, config_error = {}, nil, nil
  config_path = config.discover(project)
  if config_path then
    local ok, loaded = pcall(config.load, config_path)
    if not ok then
      config_error = tostring(loaded)
    else
      cfg = loaded
    end
  end

  local merged = config.merge(M.cli_overrides(settings), cfg, DEFAULT)

  -- Re-coerce the merged values into the shapes the run code expects.
  merged.select = as_list(merged.select)
  merged.jobs = as_positive_int(merged.jobs, 1)
  merged.editors = resolve_editors(merged.editor)
  merged.editor_explicit = merged.editor ~= nil
  merged.fail_fast = merged.fail_fast == true
  -- These are not part of the precedence ladder; carry the parsed values through.
  merged.paths = settings.paths
  merged.seed = settings.seed
  merged.failed = settings.failed
  merged.list = settings.list
  merged.verbose = settings.verbose
  merged.quiet = settings.quiet

  return merged, config_error, config_path
end

function M.main(opts)
  opts = opts or {}
  local root = opts.root or "."
  local project = opts.project or "."
  local argv = opts.argv or {}

  -- `init` is a SUBCOMMAND, dispatched before any flag/path handling so its name
  -- is never mistaken for a positional path restriction.
  if argv[1] == "init" then
    local result = require("liv.tester._init").run(project)
    io.write(result.message .. "\n")
    for _, path in ipairs(result.created) do
      io.write("  created " .. path .. "\n")
    end
    -- A refusal to clobber is a usage error (2); a successful scaffold is 0.
    return result.ok and 0 or 2
  end

  local parsed = M.parse_args(argv)

  if parsed.help then
    io.write(USAGE)
    return M.exit_code({ ran = true, failed = 0, usage_error = false })
  end
  if parsed.version then
    io.write("liv-tester " .. VERSION .. "\n")
    return M.exit_code({ ran = true, failed = 0, usage_error = false })
  end

  -- `--watch`: run once, then re-run on any change under spec/ test/ lua/ (mtime
  -- polling, pure Lua). Best-effort and never returns (Ctrl-C to stop); each
  -- iteration calls main() with `--watch` stripped so a normal single run executes.
  if parsed.watch then
    local watch = require("liv.tester._watch")
    local inner_argv = {}
    for _, tok in ipairs(argv) do
      if tok ~= "--watch" then
        inner_argv[#inner_argv + 1] = tok
      end
    end
    io.write("watching spec/ test/ lua/ for changes (Ctrl-C to stop)\n")
    watch.loop(watch.dirs(project), function()
      M.main({ root = root, project = project, argv = inner_argv })
    end)
    return M.exit_code({ ran = true, failed = 0, usage_error = false })
  end

  local settings, config_error, config_path = resolve_settings(project, parsed)
  if config_error then
    io.write(config_error .. "\n")
    return M.exit_code({ ran = false, failed = 0, usage_error = true })
  end
  if config_path then
    io.write("using config " .. config_path .. "\n")
  end

  -- Resolve the reporter: an explicit `--reporter` (or config) must name a known
  -- one (else a usage error, exit 2); otherwise the default is chosen by whether
  -- stdout is a terminal (spec) or not (tap).
  local is_tty = stdout_is_tty()
  local reporter_name = settings.reporter or M.default_reporter(is_tty)
  local reporter_factory = reporters.get(reporter_name)
  if not reporter_factory then
    io.write("unknown reporter: " .. reporter_name .. "\n")
    io.write("known reporters: spec, tap, jsonl, junit\n")
    return M.exit_code({ ran = false, failed = 0, usage_error = true })
  end

  -- The selector filter, ANDed with the `--failed` exact-name filter when set.
  local select_filter = select.compile(settings.select)
  local failed_names = nil
  if settings.failed then
    local stored = failed_store.load(failed_store.state_path(project))
    failed_names = {}
    for _, f in ipairs(stored) do
      failed_names[#failed_names + 1] = f.name
    end
  end
  local filter = select_filter
  if failed_names then
    local failed_filter = failed_store.filter(failed_names)
    filter = function(title, tags)
      return failed_filter(title, tags) and select_filter(title, tags)
    end
  end

  -- A seed (when given) is echoed so a failing order is reproducible. Randomized
  -- order is strictly OPT-IN: a default run stays in declaration order, so the
  -- suite's own green gate is never flipped by latent order-coupling.
  if settings.seed ~= nil then
    io.write("random seed: " .. tostring(settings.seed) .. "\n")
  end

  local tester = require("liv.tester")
  tester.install()

  -- Discover spec/test files, restrict by positional paths, then by the config's
  -- includes/excludes globs (a project-level scope on top of the CLI's path args).
  local function scope(files)
    files = restrict(files, settings.paths)
    return config.filter_files(files, settings.includes, settings.excludes)
  end

  -- `--list` previews the candidate test names without running anything, so an
  -- author can confirm a selector before a (possibly slow) run. L1 is enumerated
  -- in-process; L3 files are listed by path (enumerating their names would need an
  -- editor spawn per file).
  if settings.list then
    local l1 = scope(discover(project .. "/spec"))
    run_l1_register_only(l1, tester, filter)
    for _, name in ipairs(tester.list({ filter = filter })) do
      io.write(name .. "\n")
    end
    local l3 = scope(discover(project .. "/test"))
    for _, file in ipairs(l3) do
      io.write("L3 " .. file .. "\n")
    end
    return M.exit_code({ ran = (#l1 + #l3) > 0, failed = 0, usage_error = false })
  end

  local total_fail, ran_any = 0, false
  -- Failing test names accumulated across BOTH layers, persisted for `--failed`.
  local run_failures = {}

  local l1 = scope(discover(project .. "/spec"))
  if #l1 > 0 then
    ran_any = true
    -- The reporter renders the per-test L1 detail; the roll-up line below is the
    -- CLI's cross-layer aggregation and is always printed verbatim.
    local reporter = reporter_factory({
      write = io.write,
      color = is_tty,
      verbose = settings.verbose,
      quiet = settings.quiet,
    })
    local p, f, s, failures, load_failures = run_l1(l1, tester, filter, reporter, settings.seed)
    total_fail = total_fail + f
    -- Persist every L1 failure by name + origin (file:line captured at it()).
    for _, fail in ipairs(failures) do
      run_failures[#run_failures + 1] = { name = fail.name, file = fail.file, line = fail.line }
    end
    -- Load/register failures precede any test event, so the reporter never sees
    -- them; surface them explicitly so a spec that fails to load is not invisible.
    for _, lf in ipairs(load_failures) do
      io.write("  FAIL " .. lf.name .. "\n")
      io.write("    " .. tostring(lf.err):gsub("\n", "\n    ") .. "\n")
    end
    io.write(fmt_layer("L1 (no editor)", p, f, s))
  end

  local l3 = scope(discover(project .. "/test"))
  if #l3 > 0 then
    local editors =
      present_editors(resolve_l3_editors(settings.editors, not settings.editor_explicit))
    if #editors > 0 then
      ran_any = true
      -- Each test/ file runs in its OWN editor invocation (per file, per editor),
      -- so a crash/hang in one file costs only that cell, never the whole layer.
      local outcome = l3runner.run({
        files = l3,
        editors = editors,
        jobs = settings.jobs,
        timeout = settings.timeout,
        fail_fast = settings.fail_fast,
        max_failures = settings.max_failures,
        build_command = l3runner.default_build_command(root, project, settings.select, {
          seed = settings.seed,
          failed_names = failed_names,
        }),
      })
      total_fail = total_fail + outcome.failed

      -- Report one summary line per editor, aggregating that editor's cells, then
      -- echo each cell's failure/timeout/crash detail. The parent only sees L3
      -- failures as `FAIL\t<name>` lines in each cell body, so persistence parses
      -- those names back out for `--failed`.
      for _, bin in ipairs(editors) do
        local p, f, s = 0, 0, 0
        local details = {}
        for _, cell in ipairs(outcome.results) do
          if cell.editor == bin then
            p = p + cell.passed
            f = f + cell.failed
            s = s + cell.skipped + (cell.status == "skipped" and 1 or 0)
            if cell.failed > 0 or cell.status == "skipped" then
              details[#details + 1] = cell.detail
            end
            -- Persist named failures only from cells that actually RAN. A crash/
            -- timeout cell's synthetic `FAIL\t<file> (<editor>) [...]` line is not
            -- a test title, so collecting it would store a name `--failed` could
            -- never rerun. (The crashed file itself is still re-run by default.)
            if cell.status == "ran" then
              for _, name in ipairs(failed_store.collect_l3_names(cell.detail or "")) do
                run_failures[#run_failures + 1] = { name = name, file = cell.file }
              end
            end
          end
        end
        io.write(fmt_layer(string.format("L3 %-5s", bin), p, f, s))
        for _, body in ipairs(details) do
          print_detail(body)
        end
      end
    end
  end

  if not ran_any then
    io.write("no specs found (expected spec/ for L1 and/or test/ for L3)\n")
  end

  -- Persist this run's failures so a later `--failed` reruns exactly them. Always
  -- rewritten (an empty list when the run was clean), so `--failed` after a green
  -- run correctly reruns nothing.
  failed_store.save(failed_store.state_path(project), run_failures)

  io.write(string.format("\nTOTAL: %d failed\n", total_fail))
  return M.exit_code({ ran = ran_any, failed = total_fail, usage_error = false })
end

return M
