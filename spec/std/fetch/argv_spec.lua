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
      "curl",
      "-sSL",
      "-i",
      "-X",
      "POST",
      "-H",
      "X-A: 1",
      "-H",
      "X-B: 2",
      "--data-binary",
      "payload",
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
      "wget",
      "-S",
      "-O",
      "-",
      "--method=PUT",
      "--header=X-A: 1",
      "--header=X-B: 2",
      "--body-data=payload",
      "http://x",
    }, got)
  end)

  describe("output", function()
    it(
      "sends the body to a file via curl -o and dumps headers to stdout via -D - (so status stays accurate, not floored to 200)",
      function()
        assert.same(
          { "curl", "-sSL", "-o", "/tmp/out", "-D", "-", "http://x" },
          argv.build("curl", "http://x", { output = "/tmp/out" })
        )
      end
    )

    it("redirects wget's -O target to the file instead of stdout", function()
      assert.same(
        { "wget", "-S", "-O", "/tmp/out", "http://x" },
        argv.build("wget", "http://x", { output = "/tmp/out" })
      )
    end)
  end)

  describe("body from a file", function()
    it("uses curl --data-binary @path for a { file = ... } body", function()
      assert.same(
        { "curl", "-sSL", "-i", "--data-binary", "@/tmp/in", "http://x" },
        argv.build("curl", "http://x", { body = { file = "/tmp/in" } })
      )
    end)

    it("uses wget --post-file for a { file = ... } body", function()
      assert.same(
        { "wget", "-S", "-O", "-", "--post-file=/tmp/in", "http://x" },
        argv.build("wget", "http://x", { body = { file = "/tmp/in" } })
      )
    end)
  end)

  describe("form (multipart/form-data)", function()
    it(
      "emits a -F flag per field, file values as @path, deterministically sorted, on curl",
      function()
        local got = argv.build("curl", "http://x", {
          form = { name = "alice", avatar = { file = "/tmp/a.png" } },
        })
        assert.same({
          "curl",
          "-sSL",
          "-i",
          "-F",
          "avatar=@/tmp/a.png",
          "-F",
          "name=alice",
          "http://x",
        }, got)
      end
    )

    it("raises on wget (no clean multipart support; gate with has('fetch.form'))", function()
      assert.has_error(function()
        argv.build("wget", "http://x", { form = { name = "alice" } })
      end)
    end)
  end)

  describe("auth (HTTP basic)", function()
    it("uses curl -u user:password", function()
      assert.same(
        { "curl", "-sSL", "-i", "-u", "bob:secret", "http://x" },
        argv.build("curl", "http://x", { auth = { user = "bob", password = "secret" } })
      )
    end)

    it("uses wget --user/--password", function()
      assert.same(
        { "wget", "-S", "-O", "-", "--user=bob", "--password=secret", "http://x" },
        argv.build("wget", "http://x", { auth = { user = "bob", password = "secret" } })
      )
    end)
  end)

  describe("proxy", function()
    it("uses curl -x", function()
      assert.same(
        { "curl", "-sSL", "-i", "-x", "http://proxy:8080", "http://x" },
        argv.build("curl", "http://x", { proxy = "http://proxy:8080" })
      )
    end)

    it("uses wget -e use_proxy=yes -e http_proxy=<url>", function()
      assert.same({
        "wget",
        "-S",
        "-O",
        "-",
        "-e",
        "use_proxy=yes",
        "-e",
        "http_proxy=http://proxy:8080",
        "http://x",
      }, argv.build("wget", "http://x", { proxy = "http://proxy:8080" }))
    end)
  end)

  describe("insecure (skip TLS verification)", function()
    it("uses curl -k", function()
      assert.same(
        { "curl", "-sSL", "-i", "-k", "https://x" },
        argv.build("curl", "https://x", { insecure = true })
      )
    end)

    it("uses wget --no-check-certificate", function()
      assert.same(
        { "wget", "-S", "-O", "-", "--no-check-certificate", "https://x" },
        argv.build("wget", "https://x", { insecure = true })
      )
    end)
  end)

  describe("http_version", function()
    it("maps to curl --http1.1", function()
      assert.same(
        { "curl", "-sSL", "-i", "--http1.1", "http://x" },
        argv.build("curl", "http://x", { http_version = "1.1" })
      )
    end)

    it("maps to curl --http2", function()
      assert.same(
        { "curl", "-sSL", "-i", "--http2", "http://x" },
        argv.build("curl", "http://x", { http_version = "2" })
      )
    end)

    it("is silently skipped on wget (no per-request HTTP version control)", function()
      assert.same(
        { "wget", "-S", "-O", "-", "http://x" },
        argv.build("wget", "http://x", { http_version = "2" })
      )
    end)
  end)
end)
