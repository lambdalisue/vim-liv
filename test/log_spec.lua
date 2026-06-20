-- L3 integration test for liv.std.log (spec 0006), on both editors. The console
-- sink is asserted via the message history (echomsg lands in :messages, the same
-- mechanism liv.std.ui.notify uses); the file sink is asserted by reading the log
-- file back. Temp files are cleaned up.
local log = require("liv.std.log")
local fs = require("liv.std.fs")
local core = require("liv.core")

describe("liv.std.log (L3)", function()
  describe("console sink", function()
    it("echoes a message at or above the threshold into :messages", function()
      local l = log.new({ name = "livtest", level = "info" })
      l.info("hello_probe")
      local msgs = core.call("execute", "messages")
      assert.is_not_nil(msgs:find("hello_probe"))
    end)

    it("drops a message below the threshold (no-op)", function()
      local l = log.new({ name = "livtest", level = "info" })
      l.debug("nope_probe")
      local msgs = core.call("execute", "messages")
      assert.is_nil(msgs:find("nope_probe"))
    end)

    it("stringifies and space-joins multiple arguments into one line", function()
      local l = log.new({ name = "livtest", level = "info" })
      l.info("count", 7, true)
      assert.is_not_nil(core.call("execute", "messages"):find("count 7 true"))
    end)

    it("honors a threshold changed at runtime via set_level", function()
      local l = log.new({ name = "livtest", level = "error" })
      l.warn("below_after_error")
      assert.is_nil(core.call("execute", "messages"):find("below_after_error"))
      l.set_level("warn")
      l.warn("above_after_lower")
      assert.is_not_nil(core.call("execute", "messages"):find("above_after_lower"))
    end)
  end)

  describe("file sink", function()
    it("appends a formatted line (level tag + message) to the log file", function()
      local path = fs.tempname()
      local l = log.new({ name = "livtest2", file = path, console = false })
      l.warn("file_probe")
      local contents = fs.read(path)
      assert.is_not_nil(contents:find("file_probe"))
      assert.is_not_nil(contents:find("WARN"))
      fs.remove(path)
    end)

    it("appends successive lines rather than truncating", function()
      local path = fs.tempname()
      local l = log.new({ name = "livtest3", file = path, console = false })
      l.info("first_line")
      l.info("second_line")
      local contents = fs.read(path)
      assert.is_not_nil(contents:find("first_line"))
      assert.is_not_nil(contents:find("second_line"))
      fs.remove(path)
    end)

    it("does not write below-threshold records to the file", function()
      local path = fs.tempname()
      local l = log.new({ name = "livtest4", file = path, console = false, level = "info" })
      l.debug("dropped_line")
      -- The file may not exist at all if nothing was ever written.
      if fs.exists(path) then
        assert.is_nil(fs.read(path):find("dropped_line"))
        fs.remove(path)
      end
    end)
  end)
end)
