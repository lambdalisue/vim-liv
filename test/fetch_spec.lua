-- L3 integration test for liv.std.fetch (spec 0006), on both editors. A real
-- round-trip needs the network, which is unsafe headless, so this asserts the
-- offline-checkable contract: the multipart-form capability gate and the wget
-- form refusal. The argv→flag mapping itself is covered exhaustively at L1
-- (spec/std/fetch/argv_spec.lua); here we confirm the same module loads and
-- behaves under a real editor.
local has = require("liv.std.has")
local argv = require("liv.std.fetch._argv")
local fn = require("liv.std.function")

describe("liv.std.fetch (L3)", function()
  it("gates multipart form upload on curl being installed", function()
    -- Multipart needs curl; wget cannot do it. The gate mirrors curl presence.
    assert.equal(fn.executable("curl") == 1, has("fetch.form"))
  end)

  it("refuses a multipart form on the wget backend (curl-only feature)", function()
    -- Independent of what is installed: the wget argv builder always raises for a
    -- form, so a wget-only host degrades loudly rather than silently dropping it.
    assert.has_error(function()
      argv.build("wget", "http://x", { form = { name = "alice" } })
    end)
  end)

  it("builds the curl multipart form on the same module under a real editor", function()
    assert.same(
      {
        "curl",
        "-sSL",
        "-i",
        "-F",
        "avatar=@/tmp/a.png",
        "-F",
        "name=alice",
        "http://x",
      },
      argv.build("curl", "http://x", {
        form = { name = "alice", avatar = { file = "/tmp/a.png" } },
      })
    )
  end)
end)
