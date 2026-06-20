-- liv.lua.hash — pure-Lua cryptographic-ish digests (MD5, SHA-1, SHA-256) and
-- HMAC over them. Editor-independent and L1-testable; all 32-bit bit math runs
-- through the liv.lua.compat shim (no native bitwise operators, per the Lua-5.1
-- dialect rule). Per-algorithm files mirror how png/zlib split (md5.lua /
-- sha1.lua / sha256.lua); this init aggregates them.
--
-- Each algorithm exposes both a raw-byte `digest` and a `hexdigest`. HMAC
-- (RFC 2104) is built on the *raw-byte* digests so the inner hash result crosses
-- into the outer hash as bytes (not hex) — the canonical HMAC correctness point.
local compat = require("liv.lua.compat")
local bxor = compat.bxor
local byte, char = string.byte, string.char

local md5 = require("liv.lua.hash.md5")
local sha1 = require("liv.lua.hash.sha1")
local sha256 = require("liv.lua.hash.sha256")

local ALGOS = { md5 = md5, sha1 = sha1, sha256 = sha256 }

---@class liv.lua.hash
local M = {}

-- MD5 hex digest of `s`.
---@param s string the message bytes
---@return string hex the 32-character lowercase hex digest
function M.md5(s)
  return md5.hexdigest(s)
end

-- SHA-1 hex digest of `s`.
---@param s string the message bytes
---@return string hex the 40-character lowercase hex digest
function M.sha1(s)
  return sha1.hexdigest(s)
end

-- SHA-256 hex digest of `s`.
---@param s string the message bytes
---@return string hex the 64-character lowercase hex digest
function M.sha256(s)
  return sha256.hexdigest(s)
end

-- XOR every byte of the 64-byte key block with the constant pad byte `b`.
local function xor_pad(block, b)
  local out = {}
  for i = 1, #block do
    out[i] = char(bxor(byte(block, i), b))
  end
  return table.concat(out)
end

-- HMAC (RFC 2104) of `msg` under `key`, using one of the named hashes
-- ("md5" / "sha1" / "sha256"). The result is a lowercase hex string.
---@param hashname "md5"|"sha1"|"sha256" the underlying hash
---@param key string the secret key
---@param msg string the message bytes
---@return string hex the lowercase hex HMAC digest
function M.hmac(hashname, key, msg)
  local algo = ALGOS[hashname]
  if algo == nil then
    error("liv.lua.hash: unknown hash for hmac: " .. tostring(hashname))
  end
  local block_size = algo.block_size

  -- Keys longer than the block size are reduced via the hash; then all keys are
  -- zero-padded out to the full block.
  if #key > block_size then
    key = algo.digest(key)
  end
  if #key < block_size then
    key = key .. string.rep("\0", block_size - #key)
  end

  local inner = algo.digest(xor_pad(key, 0x36) .. msg)
  return algo.hexdigest(xor_pad(key, 0x5c) .. inner)
end

return M
