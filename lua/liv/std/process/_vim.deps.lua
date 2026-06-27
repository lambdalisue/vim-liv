-- Dependency manifest for liv.std.process._vim (spec 0008). Its Vim 9 script
-- companion is an autoload script (autoload/liv/std/process.vim), sourced
-- automatically by Vim on the first liv#std#process#* reference rather than via
-- `require`, so static analysis cannot see it. Declare it as an autoload file so
-- the bundler vendors it into the consumer's autoload/ tree (rewriting the path
-- prefix so the vendored copy self-isolates).
return { autoload = { "liv/std/process.vim" } }
