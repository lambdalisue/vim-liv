-- liv.std.bufname — buffer-name codec for the denops/std `bufname` wire form
-- (`scheme://expr[;k=v&k=v...][#fragment]`). See spec 0006.
--
-- Placement note: this module is pure computation with no editor dependency, so
-- by the placement rule (0003) it would normally live in `liv.lua`. It lives in
-- `liv.std` deliberately, for two reasons: (1) it mirrors denops/std's
-- `bufname`, keeping the cross-editor surface aligned with that familiar
-- vocabulary; and (2) it is the naming convention for editor buffer names, used
-- alongside the editor-dependent `liv.std.buffer` module. It has no backend and
-- no `liv.has` gate — `init.lua` is a plain re-export of the pure impl.
---@class liv.std.bufname
---@field format fun(bufname: liv.std.bufname.Bufname): string
---@field parse fun(str: string): liv.std.bufname.Bufname

---@type liv.std.bufname
return require("liv.std.bufname.bufname")
