# vim-liv task runner. Run inside the Nix dev shell so stylua / luacheck / luajit /
# vim / nvim resolve to the pinned versions:  nix develop -c just <recipe>
# (or `nix develop` once, then `just <recipe>`).

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

# cross-editor suite, L1 + L3 (Vim 9 +lua AND Neovim); args -> bin/liv-tester (--select/--reporter/PATH/...)
test *args:
    luajit bin/liv-tester {{ args }}

# run the suite on Vim only; args pass through
test-vim *args:
    luajit bin/liv-tester --editor=vim {{ args }}

# run the suite on Neovim only; args pass through
test-nvim *args:
    luajit bin/liv-tester --editor=nvim {{ args }}
