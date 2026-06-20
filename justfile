# vim-liv task runner. Run inside the Nix dev shell so stylua / luacheck / luajit /
# vim / nvim resolve to the pinned versions:  nix develop -c just <recipe>
# (or `nix develop` once, then `just <recipe>`).

mod test

# default: list the recipes
default:
    @just --list

# lint + format check (the CI gate): stylua --check then luacheck
check:
    stylua --check .
    luacheck lua/ spec/ test/

# format all Lua in place
fmt:
    stylua .
