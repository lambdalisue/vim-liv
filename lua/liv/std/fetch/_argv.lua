-- liv.std.fetch._argv — pure construction of the curl/wget command line. No
-- editor dependency, so it is L1-testable on its own (the editor-bound transport
-- lives in init.lua). Both tools are first-class:
--   curl: -sSL (quiet but report errors, follow redirects) -i (status + headers
--         into stdout, ahead of the body).
--   wget: -S (response headers to stderr) -O - (body to stdout). wget follows
--         redirects by default; no -q (it would suppress -S).
local M = {}

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys) -- deterministic argv (Lua tables have no order)
  return keys
end

---@param tool "curl"|"wget"
---@param url string
---@param opts? { method?: string, headers?: table<string,string>, body?: string }
---@return string[] argv
function M.build(tool, url, opts)
  opts = opts or {}
  local a
  if tool == "wget" then
    a = { "wget", "-S", "-O", "-" }
    if opts.method then
      a[#a + 1] = "--method=" .. opts.method
    end
    if opts.headers then
      for _, k in ipairs(sorted_keys(opts.headers)) do
        a[#a + 1] = "--header=" .. k .. ": " .. opts.headers[k]
      end
    end
    if opts.body ~= nil then
      a[#a + 1] = "--body-data=" .. opts.body
    end
  else
    a = { "curl", "-sSL", "-i" }
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
    if opts.body ~= nil then
      a[#a + 1] = "--data-binary"
      a[#a + 1] = opts.body
    end
  end
  a[#a + 1] = url
  return a
end

return M
