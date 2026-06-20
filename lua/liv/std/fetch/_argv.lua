-- liv.std.fetch._argv — pure construction of the curl/wget command line. No
-- editor dependency, so it is L1-testable on its own (the editor-bound transport
-- lives in init.lua). Both tools are first-class:
--   curl: -sSL (quiet but report errors, follow redirects) -i (status + headers
--         into stdout, ahead of the body). When opts.output is set the body goes
--         to a file via -o, and the status line + headers are dumped to stdout via
--         -D - (NOT -i, which would corrupt the downloaded file) so the parsed
--         status stays accurate instead of flooring to 200.
--   wget: -S (response headers to stderr) -O - (body to stdout). wget follows
--         redirects by default; no -q (it would suppress -S). When opts.output is
--         set the -O target becomes the file instead of stdout.
--
-- Request feature coverage (curl is preferred; wget degrades where noted):
--   method/headers       — both.
--   body (string)        — curl --data-binary; wget --body-data.
--   body { file=path }   — curl --data-binary @path; wget --post-file=path.
--   output = path        — curl -o path -D - (headers to stdout); wget -O path.
--   auth { user,password}— curl -u user:pass; wget --user/--password.
--   proxy = url          — curl -x url; wget -e use_proxy=yes -e http_proxy=url.
--   insecure = true      — curl -k; wget --no-check-certificate.
--   http_version "1.1"|"2" — curl --http1.1/--http2; wget has no per-request
--                          version control, so it is silently skipped.
--   form { field=value } — multipart/form-data, curl ONLY (-F field=value, a
--                          { file = path } value becomes -F field=@path). wget
--                          has no clean multipart support, so a form on wget
--                          raises (gate with has("fetch.form")).
local M = {}

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys) -- deterministic argv (Lua tables have no order)
  return keys
end

-- Render one form field's value into curl's -F argument body. A table with a
-- `file` key means an upload (@path); anything else is a literal value.
local function form_value(value)
  if type(value) == "table" and value.file then
    return "@" .. value.file
  end
  return tostring(value)
end

---@class liv.std.fetch.opts
---@field method? string
---@field headers? table<string,string>
---@field body? string|{ file: string }
---@field output? string download the response body to this path instead of returning it
---@field form? table<string, string|{ file: string }> multipart/form-data fields (curl only)
---@field auth? { user: string, password: string } HTTP basic auth
---@field proxy? string proxy URL
---@field insecure? boolean skip TLS certificate verification
---@field http_version? "1.1"|"2" preferred HTTP version (curl only)

---@param tool "curl"|"wget"
---@param url string
---@param opts? liv.std.fetch.opts
---@return string[] argv
function M.build(tool, url, opts)
  opts = opts or {}
  local a
  if tool == "wget" then
    if opts.form then
      error(
        "liv.std.fetch: form (multipart/form-data) requires curl; wget is not supported (gate with liv.std.has('fetch.form'))"
      )
    end
    -- -O target is "-" (body to stdout) unless output redirects it to a file.
    a = { "wget", "-S", "-O", opts.output or "-" }
    if opts.method then
      a[#a + 1] = "--method=" .. opts.method
    end
    if opts.headers then
      for _, k in ipairs(sorted_keys(opts.headers)) do
        a[#a + 1] = "--header=" .. k .. ": " .. opts.headers[k]
      end
    end
    if opts.auth then
      a[#a + 1] = "--user=" .. opts.auth.user
      a[#a + 1] = "--password=" .. opts.auth.password
    end
    if opts.proxy then
      a[#a + 1] = "-e"
      a[#a + 1] = "use_proxy=yes"
      a[#a + 1] = "-e"
      a[#a + 1] = "http_proxy=" .. opts.proxy
    end
    if opts.insecure then
      a[#a + 1] = "--no-check-certificate"
    end
    -- http_version: wget has no per-request HTTP version control; skip silently.
    if type(opts.body) == "table" then
      a[#a + 1] = "--post-file=" .. opts.body.file
    elseif opts.body ~= nil then
      a[#a + 1] = "--body-data=" .. opts.body
    end
  else
    a = { "curl", "-sSL" }
    if opts.output then
      -- -o writes the body to a file; -D - dumps the status line + headers to
      -- stdout so the parsed status/headers stay ACCURATE (a 404 is not masked as
      -- 200). A plain -i would interleave the headers into the downloaded file and
      -- corrupt it, hence the separate header dump.
      a[#a + 1] = "-o"
      a[#a + 1] = opts.output
      a[#a + 1] = "-D"
      a[#a + 1] = "-"
    else
      a[#a + 1] = "-i"
    end
    if opts.method then
      a[#a + 1] = "-X"
      a[#a + 1] = opts.method
    end
    if opts.headers then
      for _, k in ipairs(sorted_keys(opts.headers)) do
        a[#a + 1] = "-H"
        a[#a + 1] = k .. ": " .. opts.headers[k]
      end
    end
    if opts.auth then
      a[#a + 1] = "-u"
      a[#a + 1] = opts.auth.user .. ":" .. opts.auth.password
    end
    if opts.proxy then
      a[#a + 1] = "-x"
      a[#a + 1] = opts.proxy
    end
    if opts.insecure then
      a[#a + 1] = "-k"
    end
    if opts.http_version == "1.1" then
      a[#a + 1] = "--http1.1"
    elseif opts.http_version == "2" then
      a[#a + 1] = "--http2"
    end
    if opts.form then
      for _, k in ipairs(sorted_keys(opts.form)) do
        a[#a + 1] = "-F"
        a[#a + 1] = k .. "=" .. form_value(opts.form[k])
      end
    end
    if type(opts.body) == "table" then
      a[#a + 1] = "--data-binary"
      a[#a + 1] = "@" .. opts.body.file
    elseif opts.body ~= nil then
      a[#a + 1] = "--data-binary"
      a[#a + 1] = opts.body
    end
  end
  a[#a + 1] = url
  return a
end

return M
