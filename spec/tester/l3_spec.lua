-- L1 self-test for the liv.tester L3 orchestrator (spec 0010, Phase 2).
--
-- P2's value is the supervision machinery: per-file process isolation, a
-- per-file timeout that SIGTERM-kills a hung child, a crashed child (no result
-- file) counted as a failure naming file+editor, parallelism, and fail-fast.
-- These tests exercise that REAL machinery against REAL subprocesses by
-- injecting `build_command` — a fake child command per (file, editor). The
-- fakes are shell one-liners (pass / crash / hang), so the suite stays
-- editor-free (L1) yet still drives genuine spawn/poll/kill code.
local l3 = require("liv.tester._l3")

-- A `build_command` that writes a fixed RESULT line to OUT for every cell. The
-- per-file body is chosen by the file's basename via `bodies[basename]`.
local function fake_builder(bodies)
  return function(file, _editor, out)
    local body = bodies[file] or "exit 0"
    -- `body` may write OUT itself (pass) or not (crash/hang). OUT is exported.
    return string.format("OUT='%s'; %s", out, body)
  end
end

-- Index a result list by "file\teditor" for order-independent assertions.
local function by_cell(results)
  local index = {}
  for _, r in ipairs(results) do
    index[r.file .. "\t" .. r.editor] = r
  end
  return index
end

describe("liv.tester._l3 orchestrator", function()
  it("isolates files: a failing file does not lose a passing file's result", function()
    local outcome = l3.run({
      files = { "pass_spec.lua", "fail_spec.lua" },
      editors = { "nvim" },
      jobs = 1,
      timeout = 5,
      build_command = fake_builder({
        ["pass_spec.lua"] = "printf 'RESULT\\t2\\t0\\t0\\n' > \"$OUT\"",
        ["fail_spec.lua"] = "printf 'RESULT\\t0\\t1\\t0\\n' > \"$OUT\"",
      }),
    })
    local cells = by_cell(outcome.results)
    assert.equal(2, cells["pass_spec.lua\tnvim"].passed)
    assert.equal(0, cells["pass_spec.lua\tnvim"].failed)
    assert.equal(1, cells["fail_spec.lua\tnvim"].failed)
    assert.equal(2, outcome.passed)
    assert.equal(1, outcome.failed)
  end)

  it("surfaces a child's per-test records (events payload) on the cell", function()
    local layer = require("liv.tester._layer")
    local events = {
      { "suite_enter", "backend" },
      { "test_end", { name = "backend ok", status = "passed", duration = 0.01 } },
      { "test_end", { name = "backend bad", status = "failed", duration = 0.02, error = "boom" } },
      { "suite_leave", "backend" },
    }
    local payload = layer.serialize(events)
    -- Write the payload to a temp file the fake child cats into OUT after RESULT.
    local pf = os.tmpname()
    local h = assert(io.open(pf, "w"))
    h:write(payload)
    h:close()
    local outcome = l3.run({
      files = { "ev_spec.lua" },
      editors = { "nvim" },
      jobs = 1,
      timeout = 5,
      build_command = fake_builder({
        ["ev_spec.lua"] = "{ printf 'RESULT\\t1\\t1\\t0\\n'; printf 'EVENTS\\n'; cat '"
          .. pf
          .. '\'; } > "$OUT"',
      }),
    })
    os.remove(pf)
    local r = outcome.results[1]
    assert.is_table(r.records)
    -- The per-test detail round-trips into structured records the CLI can replay.
    assert.same(events, r.records)
    assert.equal(1, r.passed)
    assert.equal(1, r.failed)
  end)

  it("synthesizes a failed record for a crashed cell (so it is not invisible)", function()
    local outcome = l3.run({
      files = { "boom_spec.lua" },
      editors = { "nvim" },
      jobs = 1,
      timeout = 5,
      build_command = fake_builder({
        ["boom_spec.lua"] = "exit 1", -- writes no OUT
      }),
    })
    local r = outcome.results[1]
    -- The crash contributes exactly one failed per-test record naming file+editor.
    assert.is_table(r.records)
    assert.equal(1, #r.records)
    assert.equal("test_end", r.records[1][1])
    assert.equal("failed", r.records[1][2].status)
    assert.is_not_nil(r.records[1][2].name:find("boom_spec.lua", 1, true))
    assert.is_not_nil(r.records[1][2].name:find("nvim", 1, true))
  end)

  it("counts a crashed child (no result file) as a failure naming file+editor", function()
    local outcome = l3.run({
      files = { "crash_spec.lua" },
      editors = { "nvim" },
      jobs = 1,
      timeout = 5,
      build_command = fake_builder({
        ["crash_spec.lua"] = "exit 1", -- writes no OUT
      }),
    })
    local r = outcome.results[1]
    assert.equal("crash_spec.lua", r.file)
    assert.equal("nvim", r.editor)
    assert.equal(1, r.failed)
    assert.equal(1, outcome.failed)
    assert.is_string(r.detail)
    assert.is_not_nil(r.detail:find("crash_spec.lua", 1, true))
    assert.is_not_nil(r.detail:find("nvim", 1, true))
  end)

  it("SIGTERM-kills a hung child on timeout and counts it as a failure", function()
    local started = os.time()
    local outcome = l3.run({
      files = { "hang_spec.lua" },
      editors = { "nvim" },
      jobs = 1,
      timeout = 1, -- seconds; the fake sleeps far longer
      build_command = fake_builder({
        ["hang_spec.lua"] = "sleep 30", -- never writes OUT
      }),
    })
    local elapsed = os.time() - started
    assert.equal(1, outcome.failed)
    assert.is_not_nil(outcome.results[1].detail:find("timeout", 1, true))
    -- The timeout must fire well before the 30s sleep would end.
    assert.is_true(elapsed < 15)
  end)

  it("aggregates deterministically under parallelism (jobs > 1)", function()
    local outcome = l3.run({
      files = { "a_spec.lua", "b_spec.lua", "c_spec.lua" },
      editors = { "nvim" },
      jobs = 3,
      timeout = 5,
      build_command = fake_builder({
        ["a_spec.lua"] = "printf 'RESULT\\t1\\t0\\t0\\n' > \"$OUT\"",
        ["b_spec.lua"] = "printf 'RESULT\\t1\\t0\\t0\\n' > \"$OUT\"",
        ["c_spec.lua"] = "printf 'RESULT\\t1\\t0\\t0\\n' > \"$OUT\"",
      }),
    })
    -- Results are emitted in file-order regardless of completion order.
    assert.same(
      { "a_spec.lua", "b_spec.lua", "c_spec.lua" },
      { outcome.results[1].file, outcome.results[2].file, outcome.results[3].file }
    )
    assert.equal(3, outcome.passed)
    assert.equal(0, outcome.failed)
  end)

  it("never runs the SAME file on two editors at once (shared per-file state)", function()
    -- A test file's external side effects (e.g. a hardcoded temp dir) are
    -- per-file global, so the same file on two editors must serialize even under
    -- --jobs > 1. The fake records an overlap whenever a second child for the
    -- same file starts while the first still holds the lock.
    local tmp = os.tmpname()
    os.remove(tmp)
    local dir = tmp .. ".d"
    os.execute("mkdir -p " .. dir)
    local active = dir .. "/active" -- one marker line per concurrently-live child
    local overlap = dir .. "/overlap"
    local outcome = l3.run({
      files = { "shared_spec.lua" },
      editors = { "nvim", "vim" },
      jobs = 2,
      timeout = 5,
      build_command = function(_file, editor, out)
        -- Mark active for the run window; if more than one child is active at the
        -- same time, record an overlap. The window (sleep) is wide enough that a
        -- concurrent launch is certain to be caught.
        return string.format(
          "OUT='%s'; ACT='%s'; OVER='%s'; "
            .. 'echo %s >> "$ACT"; sleep 0.4; '
            .. 'if [ "$(wc -l < "$ACT")" -gt 1 ]; then echo x >> "$OVER"; fi; '
            .. ': > "$ACT"; '
            .. "printf 'RESULT\\t1\\t0\\t0\\n' > \"$OUT\"",
          out,
          active,
          overlap,
          editor
        )
      end,
    })
    local overlapped = io.open(overlap, "r")
    if overlapped then
      overlapped:close()
    end
    os.execute("rm -rf " .. dir)
    assert.is_nil(overlapped) -- the two editors must not have run concurrently
    assert.equal(2, outcome.passed)
  end)

  it("runs each (file, editor) cell so both editors are isolated per file", function()
    local outcome = l3.run({
      files = { "x_spec.lua" },
      editors = { "nvim", "vim" },
      jobs = 1,
      timeout = 5,
      build_command = fake_builder({
        ["x_spec.lua"] = "printf 'RESULT\\t1\\t0\\t0\\n' > \"$OUT\"",
      }),
    })
    local cells = by_cell(outcome.results)
    assert.is_not_nil(cells["x_spec.lua\tnvim"])
    assert.is_not_nil(cells["x_spec.lua\tvim"])
    assert.equal(2, outcome.passed)
  end)

  it("fail-fast stops launching new cells and marks the remainder skipped", function()
    local launched = {}
    local outcome = l3.run({
      files = { "f1_spec.lua", "f2_spec.lua", "f3_spec.lua" },
      editors = { "nvim" },
      jobs = 1,
      timeout = 5,
      fail_fast = true,
      build_command = function(file, _editor, out)
        launched[#launched + 1] = file
        local body
        if file == "f1_spec.lua" then
          body = "printf 'RESULT\\t0\\t1\\t0\\n' > \"$OUT\""
        else
          body = "printf 'RESULT\\t1\\t0\\t0\\n' > \"$OUT\""
        end
        return string.format("OUT='%s'; %s", out, body)
      end,
    })
    -- The first cell fails; with jobs=1 and fail-fast, no further cells launch.
    assert.same({ "f1_spec.lua" }, launched)
    assert.equal(1, outcome.failed)
    assert.equal(2, outcome.skipped)
  end)

  it("max-failures stops launching after N failures", function()
    local launched = {}
    local outcome = l3.run({
      files = { "g1_spec.lua", "g2_spec.lua", "g3_spec.lua", "g4_spec.lua" },
      editors = { "nvim" },
      jobs = 1,
      timeout = 5,
      max_failures = 2,
      build_command = function(file, _editor, out)
        launched[#launched + 1] = file
        return string.format("OUT='%s'; printf 'RESULT\\t0\\t1\\t0\\n' > \"$OUT\"", out)
      end,
    })
    -- Two failures reach the threshold; the 3rd/4th cells never launch.
    assert.equal(2, #launched)
    assert.equal(2, outcome.failed)
    assert.equal(2, outcome.skipped)
  end)
end)
