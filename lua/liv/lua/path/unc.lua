-- Windows/UNC path flavour: both "/" and "\\" are separators; drive paths
-- (C:\) are absolute; output uses "\\". Public so it can be used explicitly
-- even on POSIX.
return require("liv.lua.path._build")({
  sep = "\\",
  sep_class = "/\\",
  drive = true,
})
