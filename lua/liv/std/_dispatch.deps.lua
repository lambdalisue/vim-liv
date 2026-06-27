-- Dependency manifest for liv.std._dispatch (spec 0008). Its Vim 9 script
-- companion is an autoload script (autoload/liv/std/dispatch.vim), sourced
-- automatically by Vim on the first liv#std#dispatch#* reference rather than via
-- `require`, so static analysis cannot see it. Declare it as an autoload file so
-- the bundler vendors it into the consumer's autoload/ tree (rewriting the path
-- prefix so the vendored copy self-isolates).
return { autoload = { "liv/std/dispatch.vim" } }
