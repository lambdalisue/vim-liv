-- L1 self-test for liv.tester._layer — the cross-layer event plumbing that lets
-- ONE reporter render every layer (L1 + each L3 editor) with continuous numbering
-- and a section header per layer (spec 0010).
--
-- Two pieces are tested:
--   recorder()  — a capturing reporter that records a layer's ordered event
--                 stream (suite enter/leave + per-test reports), so an L3 child
--                 can serialize what happened inside the editor.
--   forwarder() — wraps the MAIN reporter; the CLI feeds each layer's events
--                 through it stamping the layer tag, emitting on_layer_enter once
--                 per layer and stamping report.layer, but NEVER forwarding the
--                 per-layer run_start/run_end (the CLI owns those once).
local layer = require("liv.tester._layer")

-- A capturing main reporter: records the calls the forwarder makes onto it.
local function spy()
  local calls = {}
  return calls,
    {
      on_run_start = function(ctx)
        calls[#calls + 1] = { "run_start", ctx }
      end,
      on_layer_enter = function(name)
        calls[#calls + 1] = { "layer_enter", name }
      end,
      on_suite_enter = function(name)
        calls[#calls + 1] = { "suite_enter", name }
      end,
      on_suite_leave = function(name)
        calls[#calls + 1] = { "suite_leave", name }
      end,
      on_test_start = function(name)
        calls[#calls + 1] = { "test_start", name }
      end,
      on_test_end = function(report)
        calls[#calls + 1] = { "test_end", report }
      end,
      on_run_end = function(stats)
        calls[#calls + 1] = { "run_end", stats }
      end,
    }
end

describe("liv.tester._layer.recorder", function()
  it("records the ordered event stream of a run as plain data", function()
    local rec = layer.recorder()
    rec.reporter.on_run_start({})
    rec.reporter.on_suite_enter("g")
    rec.reporter.on_test_start("g a")
    rec.reporter.on_test_end({ name = "g a", status = "passed", duration = 0.01 })
    rec.reporter.on_suite_leave("g")
    rec.reporter.on_run_end({ passed = 1, failed = 0, skipped = 0, duration = 0.01 })
    local events = rec.events()
    -- Suite + test events are captured (run_start/run_end are the CLI's, not a
    -- per-layer concern, so they are dropped from the recorded stream).
    assert.same({ "suite_enter", "g" }, events[1])
    assert.same({ "test_end", { name = "g a", status = "passed", duration = 0.01 } }, events[2])
    assert.same({ "suite_leave", "g" }, events[3])
  end)
end)

describe("liv.tester._layer serialize / deserialize", function()
  it("round-trips an event stream through a Lua string verbatim", function()
    local rec = layer.recorder()
    rec.reporter.on_suite_enter("backend")
    rec.reporter.on_test_end({ name = "backend ok", status = "passed", duration = 0.5 })
    rec.reporter.on_suite_leave("backend")
    local text = layer.serialize(rec.events())
    assert.is_string(text)
    local back = layer.deserialize(text)
    assert.same(rec.events(), back)
  end)

  it("survives multi-line error text with tabs and quotes", function()
    local rec = layer.recorder()
    rec.reporter.on_test_end({
      name = 'a "quoted" name',
      status = "failed",
      duration = 0.1,
      error = 'line one\nline\ttwo\n"three"',
      file = "x_spec.lua",
      line = 7,
    })
    local back = layer.deserialize(layer.serialize(rec.events()))
    assert.equal('line one\nline\ttwo\n"three"', back[1][2].error)
    assert.equal("x_spec.lua", back[1][2].file)
    assert.equal(7, back[1][2].line)
  end)

  it("deserializing a truncated/garbage payload yields nil (a crash signal)", function()
    assert.is_nil(layer.deserialize("return {{ broken"))
    assert.is_nil(layer.deserialize(""))
  end)
end)

describe("liv.tester._layer.forwarder", function()
  it("emits on_layer_enter once and stamps each report's layer", function()
    local calls, main = spy()
    local fwd = layer.forwarder(main, "L1")
    fwd.on_suite_enter("g")
    fwd.on_test_end({ name = "g a", status = "passed", duration = 0 })
    fwd.on_suite_leave("g")
    -- The first event triggers on_layer_enter("L1"); the report is stamped.
    assert.same({ "layer_enter", "L1" }, calls[1])
    assert.same({ "suite_enter", "g" }, calls[2])
    assert.equal("test_end", calls[3][1])
    assert.equal("L1", calls[3][2].layer)
  end)

  it("never forwards a per-layer run_start or run_end (the CLI owns those)", function()
    local calls, main = spy()
    local fwd = layer.forwarder(main, "L1")
    fwd.on_run_start({})
    fwd.on_test_end({ name = "a", status = "passed", duration = 0 })
    fwd.on_run_end({ passed = 1, failed = 0, skipped = 0 })
    for _, c in ipairs(calls) do
      assert.is_true(c[1] ~= "run_start")
      assert.is_true(c[1] ~= "run_end")
    end
  end)

  it("replays a recorded event stream into the main reporter under a layer tag", function()
    local calls, main = spy()
    local fwd = layer.forwarder(main, "L3:nvim")
    layer.replay(fwd, {
      { "suite_enter", "backend" },
      { "test_end", { name = "backend ok", status = "passed", duration = 0 } },
      { "suite_leave", "backend" },
    })
    assert.same({ "layer_enter", "L3:nvim" }, calls[1])
    assert.equal("L3:nvim", calls[3][2].layer)
  end)
end)
