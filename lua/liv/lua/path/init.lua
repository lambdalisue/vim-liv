-- liv.lua.path — path manipulation (spec 0006).
--
-- Returns the platform-default flavour (chosen once at import from the Lua
-- build's separator) while also exposing both flavours explicitly as `.posix`
-- and `.unc`, so code can process foreign-style paths on either host.
local posix = require("liv.lua.path.posix")
local unc = require("liv.lua.path.unc")

local default = package.config:sub(1, 1) == "\\" and unc or posix

---@class liv.lua.path : liv.lua.path.Flavour
---@field posix liv.lua.path.Flavour POSIX path flavour (`/` separator).
---@field unc liv.lua.path.Flavour Windows/UNC path flavour (`\` separator, drive paths).

---@type liv.lua.path
return setmetatable({ posix = posix, unc = unc }, { __index = default })
