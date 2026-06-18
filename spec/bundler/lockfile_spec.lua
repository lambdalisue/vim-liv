-- L1 unit test for liv.bundler.lockfile. Pure, no editor.
local lockfile = require("liv.bundler.lockfile")

describe("liv.bundler.lockfile", function()
  local lock = {
    modules = {
      ["liv.std.buffer"] = { source = "path", version = nil, hash = "aabbccdd" },
      ["liv.core"] = { source = "git", version = "deadbee", hash = "11223344" },
    },
  }

  it("serializes deterministically, sorted by module name", function()
    local s = lockfile.serialize(lock)
    assert.equal(
      "liv-lockfile 1\n"
        .. "liv.core\tgit\tdeadbee\t11223344\n"
        .. "liv.std.buffer\tpath\t-\taabbccdd\n",
      s
    )
  end)

  it("round-trips through parse", function()
    local back = lockfile.parse(lockfile.serialize(lock))
    assert.same(lock.modules, back.modules)
  end)

  it("hashes content stably and differs on change", function()
    assert.equal(lockfile.hash("hello"), lockfile.hash("hello"))
    assert.are_not.equal(lockfile.hash("hello"), lockfile.hash("hellp"))
    assert.equal(8, #lockfile.hash("anything"))
  end)
end)
