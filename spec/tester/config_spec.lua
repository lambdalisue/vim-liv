-- L1 self-test for liv.tester._config — config-file loading, walk-up discovery,
-- and the precedence ladder CLI > config > default (spec 0010).
local config = require("liv.tester._config")

describe("liv.tester._config.load", function()
  it("loads a Lua file that returns a table", function()
    local path = os.tmpname()
    local fh = assert(io.open(path, "w"))
    fh:write("return { reporter = 'tap', jobs = 4, select = { 'tag:smoke' } }\n")
    fh:close()
    local cfg = config.load(path)
    os.remove(path)
    assert.equal("tap", cfg.reporter)
    assert.equal(4, cfg.jobs)
    assert.same({ "tag:smoke" }, cfg.select)
  end)

  it("errors when the file does not return a table", function()
    local path = os.tmpname()
    local fh = assert(io.open(path, "w"))
    fh:write("return 42\n")
    fh:close()
    assert.has_error(function()
      config.load(path)
    end)
    os.remove(path)
  end)

  it("errors when the file has a syntax error", function()
    local path = os.tmpname()
    local fh = assert(io.open(path, "w"))
    fh:write("return { = }\n")
    fh:close()
    assert.has_error(function()
      config.load(path)
    end)
    os.remove(path)
  end)
end)

describe("liv.tester._config.discover", function()
  it("finds a .liv-tester.lua by walking up from a start directory", function()
    local base = os.tmpname()
    os.remove(base)
    os.execute("mkdir -p " .. base .. "/a/b/c")
    local fh = assert(io.open(base .. "/a/.liv-tester.lua", "w"))
    fh:write("return {}\n")
    fh:close()
    local found = config.discover(base .. "/a/b/c")
    os.execute("rm -rf " .. base)
    assert.equal(base .. "/a/.liv-tester.lua", found)
  end)

  it("returns nil when no config exists up the tree", function()
    local base = os.tmpname()
    os.remove(base)
    os.execute("mkdir -p " .. base .. "/x/y")
    local found = config.discover(base .. "/x/y")
    os.execute("rm -rf " .. base)
    assert.is_nil(found)
  end)
end)

describe("liv.tester._config.merge (precedence CLI > config > default)", function()
  it("uses the default when neither CLI nor config supplies a value", function()
    local merged = config.merge({ jobs = nil }, {}, { jobs = 1 })
    assert.equal(1, merged.jobs)
  end)

  it("config overrides the default", function()
    local merged = config.merge({ jobs = nil }, { jobs = 8 }, { jobs = 1 })
    assert.equal(8, merged.jobs)
  end)

  it("CLI overrides config and default", function()
    local merged = config.merge({ jobs = 2 }, { jobs = 8 }, { jobs = 1 })
    assert.equal(2, merged.jobs)
  end)

  it("a CLI value present but falsy still wins over config (presence, not truthiness)", function()
    local merged = config.merge({ fail_fast = false }, { fail_fast = true }, { fail_fast = false })
    -- CLI explicitly set fail_fast = false, so it wins over the config's true.
    assert.is_false(merged.fail_fast)
  end)

  it("merges per-key: CLI for one, config for another, default for a third", function()
    local merged = config.merge(
      { reporter = "tap" },
      { jobs = 4 },
      { reporter = "spec", jobs = 1, timeout = 60 }
    )
    assert.equal("tap", merged.reporter)
    assert.equal(4, merged.jobs)
    assert.equal(60, merged.timeout)
  end)
end)

describe("liv.tester._config.filter_files (includes/excludes globs)", function()
  local files = {
    "spec/a_spec.lua",
    "spec/sub/b_spec.lua",
    "test/c_spec.lua",
    "spec/slow/d_spec.lua",
  }

  it("keeps all files when neither includes nor excludes is set", function()
    assert.same(files, config.filter_files(files, nil, nil))
  end)

  it("includes keeps only files matching any include glob", function()
    local kept = config.filter_files(files, { "spec/*" }, nil)
    -- `*` matches within a path segment but not `/`, so only the top-level spec.
    assert.same({ "spec/a_spec.lua" }, kept)
  end)

  it("a `**`-style include via plain substring works through a glob segment", function()
    local kept = config.filter_files(files, { "test/*" }, nil)
    assert.same({ "test/c_spec.lua" }, kept)
  end)

  it("excludes drops files matching any exclude glob", function()
    local kept = config.filter_files(files, nil, { "spec/slow/*" })
    assert.same({
      "spec/a_spec.lua",
      "spec/sub/b_spec.lua",
      "test/c_spec.lua",
    }, kept)
  end)

  it("excludes win over includes", function()
    local kept = config.filter_files(files, { "spec/sub/*", "spec/slow/*" }, { "spec/slow/*" })
    assert.same({ "spec/sub/b_spec.lua" }, kept)
  end)

  it("treats a glob literally except for * (magic chars escaped)", function()
    local kept = config.filter_files({ "a.b_spec.lua", "axb_spec.lua" }, { "a.b*" }, nil)
    -- The `.` is literal, so `axb_spec.lua` must NOT match.
    assert.same({ "a.b_spec.lua" }, kept)
  end)
end)
