-- liv.lua.argument — command-argument parser (spec 0009). Pure Lua, editor-
-- independent. liv.std.command handlers receive a RAW argument string, and every
-- plugin would otherwise re-implement flag parsing; this owns liv's own vocabulary
-- for it (modeled on Vim's `:command` arg conventions + `:edit ++opt`
-- long-options), NOT a copy of any one editor's shape.
--
-- The family is split into independent leaves so a parse-only consumer (the common
-- case) never vendors the format inverse:
--   * liv.lua.argument.parse  — `split` (quote-aware tokenizer) + `parse`.
--   * liv.lua.argument.format — `format` (rebuild a command line from a parse).
-- This barrel re-exposes the historical flat API (`split`/`parse`/`format`) for
-- back-compat; the leaves are an additive split, not a breaking move. The leaves
-- are fully independent (parse never calls format and vice versa), so each can be
-- required on its own without dragging the other in.
---@class liv.lua.argument
---@field split fun(str: string): string[]
---@field parse fun(input: string|string[]): table, table, string[]
---@field format fun(opts?: table, flags?: table, rest?: string[]): string
local parse = require("liv.lua.argument.parse")
local format = require("liv.lua.argument.format")

local M = {}
M.split = parse.split
M.parse = parse.parse
M.format = format.format
return M
