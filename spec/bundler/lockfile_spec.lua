-- L1 unit test for liv.bundler.lockfile. Pure, no editor.
local lockfile = require("liv.bundler.lockfile")

describe("liv.bundler.lockfile", function()
  local lock = {
    meta = { plugin = "mp", source = "path", from = "/x/lua", roots = { "liv.std.buffer" } },
    modules = {
      ["liv.std.buffer"] = { source = "path", version = nil, hash = "aabbccdd" },
      ["liv.core"] = { source = "git", version = "deadbee", hash = "11223344" },
    },
  }

  it("serializes deterministically: fixed-order meta, then sorted modules", function()
    assert.equal(
      "liv-lockfile 1\n"
        .. "@plugin\tmp\n"
        .. "@source\tpath\n"
        .. "@from\t/x/lua\n"
        .. "@roots\tliv.std.buffer\n"
        .. "\n"
        .. "liv.core\tgit\tdeadbee\t11223344\n"
        .. "liv.std.buffer\tpath\t-\taabbccdd\n",
      lockfile.serialize(lock)
    )
  end)

  it("round-trips meta and modules through parse", function()
    local back = lockfile.parse(lockfile.serialize(lock))
    assert.same(lock.modules, back.modules)
    assert.equal("mp", back.meta.plugin)
    assert.equal("path", back.meta.source)
    assert.equal("/x/lua", back.meta.from)
    assert.same({ "liv.std.buffer" }, back.meta.roots)
  end)

  it("hashes content stably and differs on change", function()
    assert.equal(lockfile.hash("hello"), lockfile.hash("hello"))
    assert.are_not.equal(lockfile.hash("hello"), lockfile.hash("hellp"))
    assert.equal(8, #lockfile.hash("anything"))
  end)
end)
