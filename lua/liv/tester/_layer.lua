-- liv.tester._layer — cross-layer event plumbing so ONE reporter renders every
-- layer (L1 in-process + each L3 editor child) with continuous numbering and a
-- section header per layer (spec 0010).
--
-- The per-test detail used to be L1-only: L3 ran inside a child editor with NO
-- reporter, and the parent saw only an aggregate RESULT line. This module is the
-- seam that fixes that:
--
--   recorder()           a capturing reporter; an L3 child drives it so the full
--                        ordered event stream (suite enter/leave + per-test
--                        reports) can be serialized out of the editor.
--   serialize/deserialize a robust round-trip for that stream — a Lua return-table
--                        file (`%q`-safe for multi-line error text), so a
--                        truncated/garbage payload simply fails to load (the
--                        crash signal the parent relies on).
--   forwarder(main,tag)  wraps the MAIN reporter: the CLI feeds each layer's
--                        events through it, which emits on_layer_enter(tag) ONCE
--                        and stamps report.layer = tag, but never forwards the
--                        per-layer run_start/run_end — the CLI owns exactly one of
--                        each across the whole run.
--   replay(fwd, events)  push a deserialized event stream through a forwarder.
--
-- Pure Lua, editor-independent, L1-testable.

local M = {}

-- A capturing reporter. Records suite enter/leave and per-test reports as plain
-- `{ tag, payload }` events, dropping on_run_start/on_run_end (those are the CLI's
-- single cross-run pair, not a per-layer concern). `events()` returns the list.
---@return { reporter: table, events: fun(): table[] }
function M.recorder()
  local events = {}
  return {
    reporter = {
      on_run_start = function() end,
      on_suite_enter = function(name)
        events[#events + 1] = { "suite_enter", name }
      end,
      on_suite_leave = function(name)
        events[#events + 1] = { "suite_leave", name }
      end,
      on_test_start = function() end,
      on_test_end = function(report)
        events[#events + 1] = { "test_end", report }
      end,
      on_run_end = function() end,
    },
    events = function()
      return events
    end,
  }
end

-- Encode a Lua string as a safe single-line literal (`%q` escapes quotes,
-- backslashes, newlines, tabs), so multi-line error text round-trips intact.
local function quote(s)
  return string.format("%q", tostring(s))
end

local function emit_report(out, report)
  out[#out + 1] = "{ name = " .. quote(report.name)
  out[#out + 1] = ", status = " .. quote(report.status)
  out[#out + 1] = string.format(", duration = %.6f", report.duration or 0)
  if report.error ~= nil then
    out[#out + 1] = ", error = " .. quote(report.error)
  end
  if report.file ~= nil then
    out[#out + 1] = ", file = " .. quote(report.file)
  end
  if report.line ~= nil then
    out[#out + 1] = string.format(", line = %d", report.line)
  end
  if report.reason ~= nil then
    out[#out + 1] = ", reason = " .. quote(report.reason)
  end
  out[#out + 1] = " }"
end

-- Serialize a recorded event stream to a Lua source string that `deserialize`
-- loads back. The shape is `return { {"suite_enter","g"}, {"test_end",{…}}, … }`.
---@param events table[]
---@return string
function M.serialize(events)
  local out = { "return {\n" }
  for _, ev in ipairs(events) do
    local tag = ev[1]
    if tag == "test_end" then
      out[#out + 1] = '  { "test_end", '
      emit_report(out, ev[2])
      out[#out + 1] = " },\n"
    else
      out[#out + 1] = "  { " .. quote(tag) .. ", " .. quote(ev[2]) .. " },\n"
    end
  end
  out[#out + 1] = "}\n"
  return table.concat(out)
end

-- Load a serialized event stream back into a list. A nil/empty/garbage payload
-- (e.g. a child that crashed mid-write) yields nil — the parent's crash signal.
---@param text string
---@return table[]|nil
function M.deserialize(text)
  if type(text) ~= "string" or text == "" then
    return nil
  end
  local chunk = loadstring and loadstring(text) or load(text)
  if not chunk then
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then
    return nil
  end
  return result
end

-- Wrap the MAIN reporter so a whole layer's events flow through under `tag`. The
-- first forwarded event emits `on_layer_enter(tag)` once (so the section header
-- precedes the layer's first suite/test); every report is stamped `layer = tag`.
-- The per-layer run_start/run_end are intentionally dropped — the CLI emits one
-- on_run_start before the first layer and one on_run_end (combined stats) after
-- the last, so numbering and the closing summary stay single and continuous.
---@param main table the resolved main reporter
---@param tag string the layer tag (e.g. "L1" / "L3:nvim")
---@return table forwarder a reporter-shaped table the CLI/replay drives
function M.forwarder(main, tag)
  local entered = false
  local function ensure_layer()
    if not entered then
      entered = true
      if main.on_layer_enter then
        main.on_layer_enter(tag)
      end
    end
  end
  return {
    on_run_start = function() end,
    on_suite_enter = function(name)
      ensure_layer()
      if main.on_suite_enter then
        main.on_suite_enter(name)
      end
    end,
    on_suite_leave = function(name)
      if main.on_suite_leave then
        main.on_suite_leave(name)
      end
    end,
    on_test_start = function(name)
      ensure_layer()
      if main.on_test_start then
        main.on_test_start(name)
      end
    end,
    on_test_end = function(report)
      ensure_layer()
      report.layer = tag
      if main.on_test_end then
        main.on_test_end(report)
      end
    end,
    on_run_end = function() end,
  }
end

-- Push a deserialized event stream through a forwarder, replaying the suite/test
-- events in order. (A `recorder` never records run_start/run_end, so there are
-- none to replay.)
---@param fwd table a forwarder (from `M.forwarder`)
---@param events table[]
function M.replay(fwd, events)
  for _, ev in ipairs(events or {}) do
    local tag = ev[1]
    if tag == "suite_enter" then
      fwd.on_suite_enter(ev[2])
    elseif tag == "suite_leave" then
      fwd.on_suite_leave(ev[2])
    elseif tag == "test_end" then
      fwd.on_test_end(ev[2])
    end
  end
end

return M
