-- Luacheck config. liv is Lua 5.1-compatible but may run on 5.1–5.4 / LuaJIT, so
-- the compat shim legitimately probes newer-stdlib fields; those are declared
-- here, not flagged. stylua owns line width.
std = "luajit"
max_line_length = false
-- Unused is a real signal; an intentionally-unused name opts out with a leading
-- underscore (e.g. `_params`, `_buf`). Allow `_`-prefixed unused vars/args/values.
ignore = { "21[1-3]/_.*", "311/_.*" }
-- The editor global: read in backends, and written (vim.bo option tables, and
-- vim.ui stubs in L3 tests), so it is a writable global, not read-only.
globals = { "vim" }
read_globals = {
  "bit",
  "bit32", -- optional bit libraries the liv.lua.compat shim probes for
  -- 5.2+ stdlib the compat shim falls back from (target Lua spans 5.1–5.4):
  table = { fields = { "unpack", "pack" } },
  package = { fields = { "searchers" } },
}
-- Test suites use the liv.tester DSL globals.
local tester_dsl = {
  "describe",
  "it",
  "before_each",
  "after_each",
  "setup",
  "teardown",
  "pending",
  "assert",
}
files["spec/**/*.lua"].read_globals = tester_dsl
files["test/**/*.lua"].read_globals = tester_dsl
