-- L1 unit test for liv.bundler.source.git with injected exec + in-memory fs.
local git = require("liv.bundler.source.git")

describe("liv.bundler.source.git", function()
  it("clones, checks out the ref, then resolves from <dest>/lua", function()
    local cmds = {}
    local exec = function(cmd)
      cmds[#cmds + 1] = cmd
      return true
    end
    local fs = {
      exists = function(p)
        return p == "/d/lua/liv/core.lua"
      end,
      read = function(p)
        return p == "/d/lua/liv/core.lua" and "CORE" or nil
      end,
    }
    local r = git.resolver("https://x/repo.git", "v1.2.3", "/d", fs, exec)
    assert.is_not_nil(cmds[1]:find("rm %-rf"))
    assert.is_not_nil(cmds[2]:find("git clone"))
    assert.is_not_nil(cmds[2]:find("repo.git"))
    assert.is_not_nil(cmds[3]:find("checkout"))
    assert.is_not_nil(cmds[3]:find("v1.2.3"))
    assert.equal("CORE", r.read("liv.core"))
  end)

  it("fetch returns nil when the clone fails", function()
    local exec = function(cmd)
      return cmd:find("git clone") == nil -- clone fails, everything else "succeeds"
    end
    assert.is_nil(git.fetch("u", nil, "/d", exec))
  end)
end)
