{
  description = "vim-liv — a Lua plugin framework for Vim 9 (+lua) and Neovim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        # `nix develop` gives the cross-editor test tools + the formatter, so local
        # dev and CI run the exact same pinned versions (see .github/workflows/ci.yml).
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.luajit # L1 host + the bin/liv-tester runner
            pkgs.neovim # L3 Neovim (headless)
            pkgs.vim-full # L3 Vim with +lua (vim-full enables the Lua interface)
            pkgs.stylua # formatter, enforced in CI
            pkgs.luajitPackages.luacheck # linter, enforced in CI
            pkgs.just # task runner (justfile recipes: check / test / fmt)
          ];
        };
      }
    );
}
