# The root flake: composes the three language flakes and the formatter's,
# one per directory, and adds the checks that read more than one
# implementation (renderings-agree above all).
#
#   nix flake check                  every check, every language
#   nix develop                      all three toolchains; .#rust, .#kotlin, .#swift for one
#   nix run .#verify                 tools/verify, every step
#   nix run .#release -- X.Y.Z       then .#publish (RELEASING.md)
#
# Each language flake is checkable alone (nix flake check ./tabular-center-rust).
# Shared inputs follow this flake's, so flake.lock here pins everything.
# Why it is shaped this way: ARCHITECTURE.md 13 and 16.
{
  description = "tabular-center — transition-matrix state machines for Rust, Kotlin, and Swift";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-swift.url = "github:NixOS/nixpkgs/nixos-unstable";

    tabular-center-rust = {
      url = "path:./tabular-center-rust";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.rust-overlay.follows = "rust-overlay";
    };
    tabular-center-kotlin = {
      url = "path:./tabular-center-kotlin";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    tabular-center-swift = {
      url = "path:./tabular-center-swift";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-swift.follows = "nixpkgs-swift";
      inputs.flake-utils.follows = "flake-utils";
    };
    tabular-center-fmt = {
      url = "path:./tabular-center-fmt";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.rust-overlay.follows = "rust-overlay";
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        langs = {
          rust = inputs.tabular-center-rust;
          kotlin = inputs.tabular-center-kotlin;
          swift = inputs.tabular-center-swift;
          fmt = inputs.tabular-center-fmt;
        };
        ctx = import ./nix/context.nix { inherit self system nixpkgs langs; };
        per = attr: nixpkgs.lib.foldl' (acc: l: acc // (l.${attr}.${system} or { })) { }
          (builtins.attrValues langs);
      in
      {
        devShells = import ./nix/shells.nix ctx // {
          rust = langs.rust.devShells.${system}.default;
          kotlin = langs.kotlin.devShells.${system}.default;
          swift = langs.swift.devShells.${system}.default;
        };

        checks = per "checks" // import ./nix/checks.nix ctx;

        apps = {
          inherit (langs.rust.apps.${system}) table-diff bench bench-asm;
          inherit (langs.fmt.apps.${system}) tb-fmt;
          inherit (langs.kotlin.apps.${system}) gradle-lock;
          inherit (langs.swift.apps.${system}) swift-lock;
        } // import ./nix/apps.nix ctx;

        packages = per "packages";

        formatter = ctx.pkgs.nixpkgs-fmt;
      });
}
