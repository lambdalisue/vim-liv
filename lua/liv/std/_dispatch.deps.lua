-- Dependency manifest for liv.std._dispatch (spec 0008). Its Vim 9 script
-- companion is sourced at runtime via a path derived from this module's own file
-- location (debug.getinfo), not via `require`, so static analysis cannot see it.
-- Declare it here so the bundler copies it beside the vendored _dispatch.lua.
return { files = { "_dispatch.vim" } }
