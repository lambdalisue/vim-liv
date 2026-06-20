# Cross-editor test suite (L1 in-process + L3 in real Vim 9 +lua AND Neovim).
# `just test` runs both editors; `just test vim` / `just test nvim` run one.

# run L1 + L3 on both editors
[default]
all:
    luajit bin/liv-tester

# run L1 + L3 on Vim only
vim:
    LIV_L3_EDITORS=vim luajit bin/liv-tester

# run L1 + L3 on Neovim only
nvim:
    LIV_L3_EDITORS=nvim luajit bin/liv-tester
