-- L3 integration test for liv.std.autocmd (spec 0006), on both editors. Uses a
-- User event (on + trigger) so the firing is deterministic and editor-neutral,
-- and asserts the handler receives a plain Lua context table.
local autocmd = require("liv.std.autocmd")

describe("liv.std.autocmd (L3)", function()
  it("runs the handler when a subscribed event fires", function()
    local n = 0
    local sub = autocmd.on("User", { pattern = "LivAuOne" }, function()
      n = n + 1
    end)
    autocmd.trigger("LivAuOne")
    assert.equal(1, n)
    sub.off()
  end)

  it("passes a plain context table with the matched name", function()
    local ctx
    local sub = autocmd.on("User", { pattern = "LivAuCtx" }, function(c)
      ctx = c
    end)
    autocmd.trigger("LivAuCtx")
    assert.equal("table", type(ctx))
    assert.equal("LivAuCtx", ctx.match)
    sub.off()
  end)

  it("off() removes the autocommand", function()
    local n = 0
    local sub = autocmd.on("User", { pattern = "LivAuOff" }, function()
      n = n + 1
    end)
    sub.off()
    autocmd.trigger("LivAuOff")
    assert.equal(0, n)
  end)

  it("off() is idempotent (calling it twice is a no-op)", function()
    local n = 0
    local sub = autocmd.on("User", { pattern = "LivAuOffTwice" }, function()
      n = n + 1
    end)
    sub.off()
    sub.off()
    autocmd.trigger("LivAuOffTwice")
    assert.equal(0, n)
  end)

  it("accepts on(events, handler) with opts omitted", function()
    local n = 0
    local sub = autocmd.on("User", function()
      n = n + 1
    end)
    autocmd.trigger("LivAuNoOpts")
    assert.equal(1, n)
    sub.off()
  end)

  it("two on() calls with the same group both fire and remove independently", function()
    local a, b = 0, 0
    local sub_a = autocmd.on(
      "User",
      { pattern = "LivAuShared", group = "LivAuSharedGrp" },
      function()
        a = a + 1
      end
    )
    local sub_b = autocmd.on(
      "User",
      { pattern = "LivAuShared", group = "LivAuSharedGrp" },
      function()
        b = b + 1
      end
    )
    -- A group is an organizational tag; each on() is its own subscription. Both
    -- fire, and off() removes exactly one, leaving the other intact.
    autocmd.trigger("LivAuShared")
    assert.equal(1, a)
    assert.equal(1, b)
    -- Removing one leaves the other intact (they are distinct subscriptions).
    sub_a.off()
    autocmd.trigger("LivAuShared")
    assert.equal(1, a)
    assert.equal(2, b)
    sub_b.off()
  end)

  it("clear(group) removes every subscription registered under that group", function()
    local a, b = 0, 0
    autocmd.on("User", { pattern = "LivAuClr", group = "LivAuClrGrp" }, function()
      a = a + 1
    end)
    autocmd.on("User", { pattern = "LivAuClr", group = "LivAuClrGrp" }, function()
      b = b + 1
    end)
    -- The canonical reload idiom: wipe the whole group, then nothing fires — and
    -- the caller need not have retained every sub handle.
    autocmd.clear("LivAuClrGrp")
    autocmd.trigger("LivAuClr")
    assert.equal(0, a)
    assert.equal(0, b)
    assert.equal(0, #autocmd.list({ event = "User", group = "LivAuClrGrp" }))
  end)

  it("clear(group) is a no-op for an unknown group", function()
    autocmd.clear("LivAuNeverAGroup") -- must not raise
  end)

  it("a group can be re-registered after clear (idempotent reload)", function()
    local n = 0
    autocmd.on("User", { pattern = "LivAuReload", group = "LivAuReloadGrp" }, function()
      n = n + 1
    end)
    autocmd.clear("LivAuReloadGrp")
    local sub = autocmd.on("User", { pattern = "LivAuReload", group = "LivAuReloadGrp" }, function()
      n = n + 1
    end)
    autocmd.trigger("LivAuReload")
    assert.equal(1, n) -- only the re-registered handler fires, exactly once
    sub.off()
  end)

  it("once fires only a single time", function()
    local n = 0
    local sub = autocmd.on("User", { pattern = "LivAuOnce", once = true }, function()
      n = n + 1
    end)
    autocmd.trigger("LivAuOnce")
    autocmd.trigger("LivAuOnce")
    assert.equal(1, n)
    sub.off()
  end)

  it("trigger with no listener is a no-op", function()
    autocmd.trigger("LivAuNobodyHome")
  end)

  it("list includes an autocommand filtered by event and group", function()
    local sub = autocmd.on(
      "User",
      { pattern = "LivAuListed", group = "LivAuListGrp" },
      function() end
    )
    local found = false
    for _, info in ipairs(autocmd.list({ event = "User", group = "LivAuListGrp" })) do
      if info.pattern == "LivAuListed" then
        found = true
        assert.equal("User", info.event)
      end
    end
    assert.is_true(found)
    sub.off()
  end)

  it("list returns an empty table when nothing matches", function()
    local result = autocmd.list({ event = "User", pattern = "LivAuNeverRegistered" })
    assert.equal("table", type(result))
    assert.equal(0, #result)
  end)

  it("buffer-scoped autocommand fires only for its buffer", function()
    local buffer = require("liv.std.buffer")
    local core = require("liv.core")
    local target = buffer.create({ listed = false, scratch = true })
    local other = buffer.create({ listed = false, scratch = true })

    local fired = 0
    local sub = autocmd.on("BufEnter", { buffer = target }, function()
      fired = fired + 1
    end)

    -- Entering the other buffer must NOT fire the target-scoped autocommand.
    core.cmd("buffer " .. other)
    assert.equal(0, fired)
    -- Entering the target buffer fires it.
    core.cmd("buffer " .. target)
    assert.equal(1, fired)

    sub.off()
    -- After off(), entering the target again does nothing.
    core.cmd("buffer " .. other)
    core.cmd("buffer " .. target)
    assert.equal(1, fired)
  end)
end)
