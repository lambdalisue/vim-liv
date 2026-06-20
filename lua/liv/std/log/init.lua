-- liv.std.log — a leveled logger (spec 0006). Editor-dependent only in its sinks:
-- the CONSOLE sink echoes through the editor (echohl + echomsg, the same
-- mechanism as liv.std.ui.notify, so the line lands in :messages) and the FILE
-- sink appends through liv.std.fs. The level math and the line formatting are the
-- pure, editor-independent liv.lua.log (L1-tested); this module composes those
-- with the editor sinks.
--
-- No backend split: the console sink is plain echohl/echomsg (identical on both
-- editors), the file sink is liv.std.fs (already cross-editor), and the default
-- log path is XDG-derived (uniform). Because the `_vim` and `_nvim` paths would
-- behave identically, this is a single module — matching the sign/text/hash
-- precedent in spec 0006 (a module whose backends would not observably differ
-- shares one path). Neovim's stdpath('log'/'state') is deliberately NOT used:
-- Vim has no equivalent, so deriving the path from $XDG_STATE_HOME keeps one
-- resolution on both editors rather than splitting for no observable gain.
--
-- Default file-path resolution (when `file = true`): a per-name file under the
-- XDG state directory —
--   <state>/liv/<name>.log
-- where <state> is $XDG_STATE_HOME, else $HOME/.local/state, else the directory
-- of fs.tempname() as a last resort (no $HOME). The parent directory is created
-- with fs.mkdir{parents=true} (idempotent). An explicit `file = "/path"` is used
-- verbatim (its parent is still created).
local core = require("liv.core")
local fs = require("liv.std.fs")
local path = require("liv.lua.path")
local logcore = require("liv.lua.log")

-- Console highlight group per level. info/trace/debug carry no emphasis (None);
-- warn/error use the editor's standard warning/error groups so the line reads at
-- the right severity — the same groups liv.std.ui.notify maps to.
local CONSOLE_HL = {
  trace = "None",
  debug = "None",
  info = "None",
  warn = "WarningMsg",
  error = "ErrorMsg",
}

-- Quote a value as a Vim string literal (single-quoted; '' escapes a quote).
-- Mirrors the helper in liv.std.ui._vim so echomsg receives a safe literal.
local function vim_str(s)
  return "'" .. tostring(s):gsub("'", "''") .. "'"
end

-- Resolve the default log path for a logger named `name`:
--   <state>/liv/<name>.log
-- See the module header for the <state> resolution order.
---@param name string
---@return string
local function default_path(name)
  local state = os.getenv("XDG_STATE_HOME")
  if state == nil or state == "" then
    local home = os.getenv("HOME")
    if home ~= nil and home ~= "" then
      state = path.join(home, ".local", "state")
    else
      -- Last resort with no $HOME: anchor under the editor's temp directory.
      state = path.dir(fs.tempname())
    end
  end
  return path.join(state, "liv", name .. ".log")
end

local M = {}

-- A logger with one method per level plus set_level. Methods are dot-called
-- (`logger.info(...)`), so they close over the logger state rather than taking
-- `self`.
---@class liv.std.log.Logger
---@field trace fun(...: any)
---@field debug fun(...: any)
---@field info fun(...: any)
---@field warn fun(...: any)
---@field error fun(...: any)
---@field set_level fun(level: string)

-- Options for new.
---@class liv.std.log.Opts
---@field name? string Plugin tag, rendered "(name)" in each line and used to
---  derive the default file path. Default: "liv".
---@field level? string Threshold level name (default "info"). Records below it
---  are no-ops on every sink.
---@field console? boolean Echo to the message area (default true). Uses the
---  level's highlight (info/trace/debug=None, warn=WarningMsg, error=ErrorMsg);
---  the line lands in :messages.
---@field file? boolean|string File sink (default false). `true` appends to the
---  default XDG path (<state>/liv/<name>.log); a string appends to that path
---  verbatim. Each enabled line is APPENDED (never truncated) with a timestamp.

-- Create a logger. Multiple arguments to a level method are each stringified
-- (tostring) and joined with a single space — there is no printf-style format
-- string (stringify+join keeps the contract simple and predictable).
---@param opts? liv.std.log.Opts
---@return liv.std.log.Logger
function M.new(opts)
  opts = opts or {}
  local name = opts.name or "liv"
  local threshold = opts.level or "info"
  -- Validate the threshold up front (raises on a typo, like the level methods).
  logcore.rank(threshold)

  local console = opts.console
  if console == nil then
    console = true
  end

  local file_path = nil
  if opts.file == true then
    file_path = default_path(name)
  elseif type(opts.file) == "string" then
    file_path = opts.file
  end

  -- Append a formatted (timestamped) line to the file sink, creating the parent
  -- directory once. fs.write truncates, so the append is read-modify-write:
  -- existing bytes + line. (Logs are low-volume; a streaming handle is not worth
  -- the cross-editor complexity here.)
  local function write_file(level, message)
    local line = logcore.format({
      level = level,
      message = message,
      time = os.time(),
      source = name,
    })
    fs.mkdir(path.dir(file_path), { parents = true })
    local existing = fs.exists(file_path) and fs.read(file_path) or ""
    fs.write(file_path, existing .. line .. "\n")
  end

  -- Echo a formatted line to the message area with the level's highlight, the
  -- same echohl/echomsg mechanism as liv.std.ui.notify (so it reaches
  -- :messages). The console line carries no timestamp (the message area is
  -- ephemeral; the file sink owns the timestamped record).
  local function write_console(level, message)
    local line = logcore.format({ level = level, message = message, source = name })
    core.cmd("echohl " .. (CONSOLE_HL[level] or "None"))
    core.cmd("echomsg " .. vim_str(line))
    core.cmd("echohl None")
  end

  -- Stringify and space-join the variadic arguments into one message body.
  local function stringify(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
      parts[i] = tostring((select(i, ...)))
    end
    return table.concat(parts, " ")
  end

  local logger = {}

  local function emit(level, ...)
    if not logcore.should_log(level, threshold) then
      return -- below threshold: a no-op on every sink
    end
    local message = stringify(...)
    if console then
      write_console(level, message)
    end
    if file_path then
      write_file(level, message)
    end
  end

  for level in pairs(logcore.levels) do
    logger[level] = function(...)
      emit(level, ...)
    end
  end

  ---@param level string a level name
  function logger.set_level(level)
    logcore.rank(level) -- validate (raises on a typo)
    threshold = level
  end

  return logger
end

return M
