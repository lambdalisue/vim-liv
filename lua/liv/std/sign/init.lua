-- liv.std.sign — sign column (gutter) markers (spec 0006). Unlike most editor
-- decoration, the `sign_*` builtins behave identically on Vim and Neovim, so this
-- is a single module with no backend split (like liv.std.function) and a base contract:
-- it works the same on both. The builtins are bound as marshaled function
-- references (vim.fn.*) — the same shape the _nvim backends use for vim.api.*, so
-- marshaling stays in core and is never hand-rolled. A native-extmark `_nvim`
-- backend (per-placement priority, statuscolumn integration) is a possible future
-- capability-gated optimization; legacy signs already give full parity here.
--
-- A `sign_*` id is only unique *within a group* (placing in two groups can yield
-- the same id), so liv allocates its own globally-unique id and remembers each
-- id's buffer and group. That lets `remove(buf, id)` take no group, and lets
-- `clear` drop exactly liv's signs. Handles follow liv's convention: buf 0/nil =
-- current. Lines are 1-based.
---@class liv.std.sign.def
---@field text? string the gutter text (1-2 cells)
---@field text_hl? string highlight group for the text
---@field line_hl? string highlight group for the whole line
---@field num_hl? string highlight group for the line number
---@class liv.std.sign.placement
---@field id integer the liv sign id
---@field line integer the 1-based line
---@field name string the defined sign name
---@field group string the placement group ("" = global)
---@field priority integer the placement priority
local core = require("liv.core")

local fn = vim.fn
local sign_define = core.marshaled(fn.sign_define)
local sign_place = core.marshaled(fn.sign_place)
local sign_unplace = core.marshaled(fn.sign_unplace)
local sign_getplaced = core.marshaled(fn.sign_getplaced)
local bufnr = core.marshaled(fn.bufnr)

local M = {}

local seq = 0
local placed = {} -- id -> { bufnr = integer, group = string }

local function resolve(buf)
  if buf == nil or buf == 0 then
    return bufnr("")
  end
  return buf
end

---@param name string
---@param def liv.std.sign.def
function M.define(name, def)
  def = def or {}
  sign_define(
    name,
    core.dict({
      text = def.text,
      texthl = def.text_hl,
      linehl = def.line_hl,
      numhl = def.num_hl,
    })
  )
end

---@param buf integer
---@param line integer
---@param name string
---@param opts? { group?: string, priority?: integer }
---@return integer id
function M.place(buf, line, name, opts)
  opts = opts or {}
  local resolved = resolve(buf)
  local group = opts.group or ""
  seq = seq + 1
  local id = seq
  sign_place(
    id,
    group,
    name,
    resolved,
    core.dict({
      lnum = line,
      priority = opts.priority,
    })
  )
  placed[id] = { bufnr = resolved, group = group }
  return id
end

---@param buf integer
---@param id integer
function M.remove(_buf, id)
  local info = placed[id]
  if not info then
    return
  end
  sign_unplace(info.group, core.dict({ buffer = info.bufnr, id = id }))
  placed[id] = nil
end

---@param buf integer
---@param opts? { group?: string }
function M.clear(buf, opts)
  opts = opts or {}
  local resolved = resolve(buf)
  local ids = {}
  for id, info in pairs(placed) do
    if info.bufnr == resolved and (not opts.group or info.group == opts.group) then
      ids[#ids + 1] = id
    end
  end
  for _, id in ipairs(ids) do
    M.remove(buf, id)
  end
end

---@param buf integer
---@param opts? { group?: string }
---@return liv.std.sign.placement[]
function M.placed(buf, opts)
  opts = opts or {}
  local resolved = resolve(buf)
  local result = sign_getplaced(resolved, core.dict({ group = opts.group or "*" }))
  local out = {}
  local entry = result[1]
  local signs = entry and entry.signs
  if signs then
    for i = 1, #signs do
      local s = signs[i]
      out[#out + 1] =
        { id = s.id, line = s.lnum, name = s.name, group = s.group, priority = s.priority }
    end
  end
  return out
end

return M
