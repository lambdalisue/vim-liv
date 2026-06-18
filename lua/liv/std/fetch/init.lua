-- liv.std.fetch — HTTP(S) fetch (spec 0006), a has-gated power feature. Neither
-- Lua nor the editor builtins provide TLS, so HTTPS is delegated to an external
-- curl (preferred — full headers/status/redirects) or, if absent, wget (a
-- degraded plain GET). Availability is reported by liv.has("fetch"); fetch()
-- raises when neither tool is present. fetch() is awaitable: call it inside an
-- async function (liv.std.task.run) — it awaits the subprocess via
-- liv.std.process and returns the response.
local fn = require("liv.std.function")
local process = require("liv.std.process")
local http = require("liv.lua.http")
local argv = require("liv.std.fetch._argv")

local function pick_tool()
  if fn.executable("curl") == 1 then
    return "curl"
  elseif fn.executable("wget") == 1 then
    return "wget"
  end
  return nil
end

local tool = pick_tool()

---@class liv.std.fetch.response
---@field status integer the HTTP status code
---@field headers table<string,string> response headers (lower-cased names)
---@field body string the response body (raw bytes)
local M = {}

---Fetch `url`. Call inside an async function (`task.run`); it awaits the request
---and returns the response. Raises if neither curl nor wget is available (gate
---with `liv.has("fetch")`) or if the subprocess fails. With only wget present the
---request degrades to a plain GET — `headers` empty. On either tool, a successful
---transfer whose response carries no parseable status line reports `status = 200`
---(never nil), so the contract is identical across curl and wget.
---@param url string
---@param opts? { method?: string, headers?: table<string,string>, body?: string }
---@return liv.std.fetch.response
function M.fetch(url, opts)
  if not tool then
    error("liv.std.fetch: neither curl nor wget is available (check liv.has('fetch'))")
  end
  local res = process.system(argv.build(tool, url, opts))
  if tool == "curl" then
    -- curl -sS returns 0 even on a 4xx/5xx (the transfer succeeded); a non-zero
    -- code is a real failure (DNS, connection, TLS).
    if res.code ~= 0 then
      error("liv.std.fetch: curl exited " .. res.code .. ": " .. (res.stderr or ""))
    end
    -- The transfer succeeded (code 0); if no status line parsed, floor to 200 —
    -- the same rule the wget path uses, so a successful transfer with no parseable
    -- status reports status=200 on both tools (never nil from one, 200 from other).
    local r = http.parse_response(res.stdout)
    return { status = r.status or 200, headers = r.headers, body = r.body }
  end
  -- wget: headers on stderr (-S), body on stdout. wget exits non-zero on a 4xx/5xx
  -- (unlike curl), so a parsed status beats the exit code; a missing status *and*
  -- a non-zero exit is the real failure (or a busybox wget that lacks -S).
  local parsed = http.parse_wget_stderr(res.stderr)
  if not parsed.status and res.code ~= 0 then
    error("liv.std.fetch: wget exited " .. res.code .. ": " .. (res.stderr or ""))
  end
  return { status = parsed.status or 200, headers = parsed.headers, body = res.stdout }
end

return M
