-- liv.std.hash — message digests (spec 0006). Editor-dependent for `sha256`,
-- which both Vim and Neovim ship as the `sha256()` builtin: routing through it
-- is the fast path (a C implementation rather than a pure-Lua block loop). The
-- pure liv.lua.hash leaves exist for editor-independent code and as the
-- implementation of `md5`/`sha1`, which the editors do NOT both guarantee as
-- builtins.
--
-- The md5/sha1 leaves are required directly (never the `liv.lua.hash` barrel):
-- the barrel re-pulls the whole family including the pure sha256 (~178 lines)
-- that std.hash never uses because sha256 goes through the editor builtin. The
-- file-grained bundler closure keeps the unused sha256 leaf out only when this
-- module imports the leaves it actually needs.
--
-- No `_nvim`/`_vim` split: `vim.fn.sha256` behaves identically on both editors
-- (same lowercase hex output), so this is the single-module precedent of
-- `liv.std.text` / `liv.std.sign` / `liv.std.function`, NOT the observable-diff
-- split of `liv.std.json` (where vim.json vs json_encode differ). The builtin is
-- bound once as a marshaled function reference, the established backend pattern.
---@class liv.std.hash
---@field sha256 fun(s: string): string lowercase 64-char hex SHA-256 (editor builtin)
---@field md5 fun(s: string): string lowercase 32-char hex MD5 (liv.lua.hash.md5 leaf)
---@field sha1 fun(s: string): string lowercase 40-char hex SHA-1 (liv.lua.hash.sha1 leaf)
local core = require("liv.core")
local md5 = require("liv.lua.hash.md5")
local sha1 = require("liv.lua.hash.sha1")

local sha256 = core.marshaled(vim.fn.sha256)

local M = {}

-- SHA-256 hex digest of `s`, via the editor's native `sha256()` builtin.
---@param s string the message bytes
---@return string hex the 64-character lowercase hex digest
function M.sha256(s)
  return sha256(s)
end

-- MD5 hex digest of `s`. The editors do not both ship an `md5()` builtin, so
-- this delegates to the pure liv.lua.hash.md5 leaf.
---@param s string the message bytes
---@return string hex the 32-character lowercase hex digest
function M.md5(s)
  return md5.hexdigest(s)
end

-- SHA-1 hex digest of `s`. The editors do not both ship a `sha1()` builtin, so
-- this delegates to the pure liv.lua.hash.sha1 leaf.
---@param s string the message bytes
---@return string hex the 40-character lowercase hex digest
function M.sha1(s)
  return sha1.hexdigest(s)
end

return M
