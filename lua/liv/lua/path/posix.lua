-- POSIX path flavour: "/" only. Backslash is an ordinary filename character.
-- Public so it can be used explicitly even on Windows.
return require("liv.lua.path._build")({
  sep = "/",
  sep_class = "/",
  drive = false,
})
