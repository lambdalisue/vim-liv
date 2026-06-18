-- L1 unit test for liv.std.fetch._argv (spec 0006). The argv builder is pure, so
-- it is tested with no editor; the editor-bound transport (init.lua) is exercised
-- manually against a live host (network-dependent, not in the suite).
local argv = require("liv.std.fetch._argv")

describe("liv.std.fetch._argv.build", function()
  it("builds a curl GET that includes headers and follows redirects", function()
    assert.same({ "curl", "-sSL", "-i", "http://x" }, argv.build("curl", "http://x"))
  end)

  it("adds method, deterministically-sorted headers, and body for curl", function()
    local got = argv.build("curl", "http://x", {
      method = "POST",
      headers = { ["X-B"] = "2", ["X-A"] = "1" },
      body = "payload",
    })
    assert.same({
      "curl", "-sSL", "-i",
      "-X", "POST",
      "-H", "X-A: 1",
      "-H", "X-B: 2",
      "--data-binary", "payload",
      "http://x",
    }, got)
  end)

  it("builds a wget GET capturing headers (-S) and body (-O -)", function()
    assert.same({ "wget", "-S", "-O", "-", "http://x" }, argv.build("wget", "http://x"))
  end)

  it("maps method/headers/body to wget's long options", function()
    local got = argv.build("wget", "http://x", {
      method = "PUT",
      headers = { ["X-B"] = "2", ["X-A"] = "1" },
      body = "payload",
    })
    assert.same({
      "wget", "-S", "-O", "-",
      "--method=PUT",
      "--header=X-A: 1",
      "--header=X-B: 2",
      "--body-data=payload",
      "http://x",
    }, got)
  end)
end)
