-- liv.tester.reporters — output reporters built on the run() EVENT INTERFACE.
--
-- A reporter is a PURE FACTORY `fun(opts) -> callbacks`, where `callbacks` is the
-- optional-callback table run() drives (on_run_start / on_suite_enter|leave /
-- on_test_start / on_test_end(report) / on_run_end(stats)). Everything a reporter
-- needs is injected via `opts`, never sniffed:
--   write           fun(string)  the output sink (default io.write)
--   color           boolean      emit ANSI escapes (the runner decides via TTY)
--   verbose/quiet   boolean      verbosity (spec reporter honours them)
--   slow_threshold  number       seconds; a test at/over it is flagged SLOW
-- This keeps reporters deterministic and L1-testable: feed a canned event stream
-- and a capturing writer, assert the bytes. Environment detection lives in the
-- CLI, which passes the resolved booleans down.

local M = {}

local function default_write(s)
  io.write(s)
end

-- Format a duration (seconds) as a compact millisecond string, e.g. "1.20ms".
local function ms(duration)
  return string.format("%.2fms", (duration or 0) * 1000)
end

-- --- spec reporter (human) --------------------------------------------------

-- ANSI palette, used only when `color` is on.
local COLORS = {
  reset = "\27[0m",
  green = "\27[32m",
  red = "\27[31m",
  yellow = "\27[33m",
  dim = "\27[2m",
  bold = "\27[1m",
}

-- A spec-style reporter: indented suite headings, ✓/✗/⊘ per test with its time,
-- a SLOW marker past the threshold, and a closing tally. Failures print their
-- error indented under the test.
function M.spec(opts)
  opts = opts or {}
  local write = opts.write or default_write
  local color = opts.color and true or false
  local slow = opts.slow_threshold
  local quiet = opts.quiet and true or false

  local function paint(name, text)
    if not color then
      return text
    end
    return (COLORS[name] or "") .. text .. COLORS.reset
  end

  local depth = 0
  local function indent()
    return string.rep("  ", depth)
  end

  return {
    on_run_start = function() end,
    on_suite_enter = function(name)
      if not quiet then
        write(indent() .. paint("bold", name) .. "\n")
      end
      depth = depth + 1
    end,
    on_suite_leave = function()
      depth = depth - 1
    end,
    on_test_start = function() end,
    on_test_end = function(report)
      local glyph, hue
      if report.status == "passed" then
        glyph, hue = "✓", "green"
      elseif report.status == "failed" then
        glyph, hue = "✗", "red"
      else
        glyph, hue = "⊘", "yellow"
      end
      local slow_tag = ""
      if slow and report.duration and report.duration >= slow and report.status ~= "skipped" then
        slow_tag = " " .. paint("yellow", "SLOW")
      end
      if not (quiet and report.status == "passed") then
        write(
          indent()
            .. paint(hue, glyph)
            .. " "
            .. report.name
            .. " "
            .. paint("dim", "(" .. ms(report.duration) .. ")")
            .. slow_tag
            .. "\n"
        )
        if report.status == "failed" and report.error then
          -- The raised error already carries its own `file:line:` prefix (Lua adds
          -- it), so don't repeat report.file/line here.
          for line in tostring(report.error):gmatch("[^\n]+") do
            write(indent() .. "    " .. paint("red", line) .. "\n")
          end
        end
      end
    end,
    on_run_end = function(stats)
      write(
        string.format(
          "\n%d passed, %d failed, %d skipped (%s)\n",
          stats.passed,
          stats.failed,
          stats.skipped,
          ms(stats.duration)
        )
      )
    end,
  }
end

-- --- TAP reporter (CI lingua franca) ----------------------------------------

-- Test Anything Protocol: a `1..N` plan, `ok`/`not ok N description` per test,
-- pending → `ok N # SKIP`, and any failure detail as `# …` diagnostics. The plan
-- is printed at run end (N is known only then), so the stream order is: results,
-- then plan — both valid TAP (a trailing plan is permitted).
function M.tap(opts)
  opts = opts or {}
  local write = opts.write or default_write
  local n = 0

  return {
    on_run_start = function() end,
    on_suite_enter = function() end,
    on_suite_leave = function() end,
    on_test_start = function() end,
    on_test_end = function(report)
      n = n + 1
      if report.status == "passed" then
        write("ok " .. n .. " - " .. report.name .. "\n")
      elseif report.status == "skipped" then
        local reason = report.reason and (" " .. report.reason) or ""
        write("ok " .. n .. " - " .. report.name .. " # SKIP" .. reason .. "\n")
      else
        write("not ok " .. n .. " - " .. report.name .. "\n")
        local detail = ""
        if report.file and report.line then
          detail = report.file .. ":" .. report.line .. ": "
        end
        for line in (detail .. tostring(report.error or "")):gmatch("[^\n]+") do
          write("# " .. line .. "\n")
        end
      end
    end,
    on_run_end = function(stats)
      write("1.." .. n .. "\n")
      write(
        string.format(
          "# passed %d failed %d skipped %d\n",
          stats.passed,
          stats.failed,
          stats.skipped
        )
      )
    end,
  }
end

-- --- JSONL reporter (machine stream) ----------------------------------------

-- A minimal, dependency-free JSON string encoder. The tester cannot use liv.json
-- (editor-dependent) — the CLI runs under a bare interpreter — so it carries its
-- own tiny encoder scoped to the value shapes a result emits (strings, numbers,
-- booleans). Strings are escaped per RFC 8259.
local function json_string(s)
  s = tostring(s)
  s = s:gsub('[%z\1-\31\\"]', function(c)
    if c == '"' then
      return '\\"'
    elseif c == "\\" then
      return "\\\\"
    elseif c == "\n" then
      return "\\n"
    elseif c == "\r" then
      return "\\r"
    elseif c == "\t" then
      return "\\t"
    end
    return string.format("\\u%04x", string.byte(c))
  end)
  return '"' .. s .. '"'
end

local function json_value(v)
  local t = type(v)
  if t == "string" then
    return json_string(v)
  elseif t == "number" then
    -- Avoid scientific notation / Inf surprises for the small values here.
    if v % 1 == 0 then
      return string.format("%d", v)
    end
    return string.format("%.6f", v)
  elseif t == "boolean" then
    return v and "true" or "false"
  end
  return "null"
end

-- Encode a flat object preserving a fixed key order, so output is deterministic.
local function json_object(pairs_list)
  local parts = {}
  for _, kv in ipairs(pairs_list) do
    parts[#parts + 1] = json_string(kv[1]) .. ":" .. json_value(kv[2])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- One JSON object per event line (newline-delimited JSON): a `test` object per
-- result and a final `summary`. Easy for a CI consumer to parse incrementally.
function M.jsonl(opts)
  opts = opts or {}
  local write = opts.write or default_write

  return {
    on_run_start = function() end,
    on_suite_enter = function() end,
    on_suite_leave = function() end,
    on_test_start = function() end,
    on_test_end = function(report)
      local fields = {
        { "type", "test" },
        { "name", report.name },
        { "status", report.status },
        { "duration", report.duration or 0 },
      }
      if report.error then
        fields[#fields + 1] = { "error", tostring(report.error) }
      end
      if report.file then
        fields[#fields + 1] = { "file", report.file }
      end
      if report.line then
        fields[#fields + 1] = { "line", report.line }
      end
      write(json_object(fields) .. "\n")
    end,
    on_run_end = function(stats)
      write(json_object({
        { "type", "summary" },
        { "passed", stats.passed },
        { "failed", stats.failed },
        { "skipped", stats.skipped },
        { "duration", stats.duration or 0 },
      }) .. "\n")
    end,
  }
end

-- --- JUnit-XML reporter -----------------------------------------------------

local function xml_escape(s)
  return tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

-- A single `<testsuite>` with one `<testcase>` per test; failures carry a
-- `<failure>` child and skips a `<skipped>` child. The suite element needs the
-- run totals, known only at run end, so all cases are buffered then flushed.
function M.junit(opts)
  opts = opts or {}
  local write = opts.write or default_write
  local cases = {}

  return {
    on_run_start = function() end,
    on_suite_enter = function() end,
    on_suite_leave = function() end,
    on_test_start = function() end,
    on_test_end = function(report)
      cases[#cases + 1] = report
    end,
    on_run_end = function(stats)
      write('<?xml version="1.0" encoding="UTF-8"?>\n')
      write(
        string.format(
          '<testsuite name="liv.tester" tests="%d" failures="%d" skipped="%d" time="%.3f">\n',
          stats.passed + stats.failed + stats.skipped,
          stats.failed,
          stats.skipped,
          stats.duration or 0
        )
      )
      for _, report in ipairs(cases) do
        write(
          string.format(
            '  <testcase name="%s" time="%.3f"',
            xml_escape(report.name),
            report.duration or 0
          )
        )
        if report.status == "failed" then
          -- Keep the attribute to the first line (a one-line summary); the full
          -- traceback would inject raw newlines into an XML attribute.
          local first = tostring(report.error or ""):match("^[^\n]*") or ""
          write(">\n")
          write('    <failure message="' .. xml_escape(first) .. '"></failure>\n')
          write("  </testcase>\n")
        elseif report.status == "skipped" then
          write(">\n")
          write("    <skipped></skipped>\n")
          write("  </testcase>\n")
        else
          write("/>\n")
        end
      end
      write("</testsuite>\n")
    end,
  }
end

-- --- Registry ---------------------------------------------------------------

local BY_NAME = {
  spec = M.spec,
  tap = M.tap,
  jsonl = M.jsonl,
  junit = M.junit,
}

-- Resolve a reporter factory by name; nil for an unknown name (the CLI turns that
-- into a usage error).
---@param name string
---@return (fun(opts: table): table)|nil
function M.get(name)
  return BY_NAME[name]
end

return M
