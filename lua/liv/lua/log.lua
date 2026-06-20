-- liv.lua.log — pure-Lua logging primitives. Editor-independent, deterministic,
-- L1-testable. Holds the LEVEL definitions, the threshold GATE, and the record
-- FORMATTER; the editor-backed sinks (console/file) live in liv.std.log, which
-- composes these. Nothing here touches the editor (not even liv.core), so the
-- formatting and gating logic is verified at L1 with an injected clock.
--
-- A "record" is a plain keyed table: { level, message, time?, source? }.
--   * level   — a level name ("trace"/"debug"/"info"/"warn"/"error").
--   * message — the already-stringified line body.
--   * time    — an optional epoch (seconds). When present the line is prefixed
--               with a UTC "YYYY-MM-DD HH:MM:SS" timestamp; when absent the line
--               carries no timestamp (unless opts.clock supplies one).
--   * source  — an optional tag (the plugin name), rendered "(source)".
--
-- The timestamp is rendered in UTC (os.date("!...")) so a formatted line reads
-- the same on every host regardless of the machine's local timezone — and so the
-- L1 assertions are timezone-independent.
local M = {}

-- Level ranks: integer order trace < debug < info < warn < error. A record is
-- emitted when its rank is >= the logger's threshold rank (see should_log).
---@class liv.lua.log.levels
---@field trace integer
---@field debug integer
---@field info integer
---@field warn integer
---@field error integer
M.levels = {
  trace = 1,
  debug = 2,
  info = 3,
  warn = 4,
  error = 5,
}

-- Reverse map rank -> name, built once from M.levels.
local names = {}
for name, r in pairs(M.levels) do
  names[r] = name
end

-- Rank of a level name. Raises (pcall-able) on an unknown name — a typo is a
-- programming error, not a value to thread through.
---@param level string a level name
---@return integer rank
function M.rank(level)
  local r = M.levels[level]
  if r == nil then
    error("liv.lua.log: unknown level " .. tostring(level), 2)
  end
  return r
end

-- Name for a rank (the inverse of rank). Raises on an out-of-range rank.
---@param rank integer a level rank
---@return string level the level name
function M.name(rank)
  local n = names[rank]
  if n == nil then
    error("liv.lua.log: unknown rank " .. tostring(rank), 2)
  end
  return n
end

-- Whether a record at `record_level` should be emitted under `threshold_level`:
-- true when the record's rank is at or above the threshold's rank.
---@param record_level string the record's level name
---@param threshold_level string the logger's threshold level name
---@return boolean
function M.should_log(record_level, threshold_level)
  return M.rank(record_level) >= M.rank(threshold_level)
end

-- Options for format.
---@class liv.lua.log.FormatOpts
---@field clock? fun(): integer Source the epoch when the record carries no
---  `time`. Injected so L1 tests stay deterministic (no real os.time).

-- Format a record into a single line. Shapes:
--   "[INFO] message"                                  (no time, no source)
--   "2026-01-01 12:00:00 [INFO] message"              (time, no source)
--   "2026-01-01 12:00:00 [INFO] (plugin) message"     (time and source)
-- The timestamp comes from record.time, else opts.clock(), else is omitted. The
-- level tag is uppercased; the source (when present) is wrapped in parentheses.
---@param record { level: string, message: string, time?: integer, source?: string }
---@param opts? liv.lua.log.FormatOpts
---@return string line
function M.format(record, opts)
  opts = opts or {}
  -- Validate the level (raises on a typo, like rank).
  M.rank(record.level)

  local epoch = record.time
  if epoch == nil and opts.clock ~= nil then
    epoch = opts.clock()
  end

  local parts = {}
  if epoch ~= nil then
    -- "!" selects UTC so the line is host-timezone-independent.
    parts[#parts + 1] = os.date("!%Y-%m-%d %H:%M:%S", epoch)
  end
  parts[#parts + 1] = "[" .. record.level:upper() .. "]"
  if record.source ~= nil then
    parts[#parts + 1] = "(" .. record.source .. ")"
  end
  parts[#parts + 1] = record.message
  return table.concat(parts, " ")
end

return M
