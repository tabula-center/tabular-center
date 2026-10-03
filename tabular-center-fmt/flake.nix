# The formatter's flake: tabular-center-fmt, which aligns the cells of `.tb.`
# matrix files (spec/tabular-center-fmt.md). It belongs to the format rather
# than to a language, reads nothing outside this directory, and needs only a
# Rust toolchain.
#
#   nix flake check ./tabular-center-fmt
#   nix run .#tb-fmt [-- --check]
{
  description = "tabular-center-fmt: aligns the cells of .tb. matrix files";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        ctx = import ./nix/context.nix { inherit self system nixpkgs rust-overlay; };
      in
      {
        devShells.default = ctx.mkShell;
        checks = import ./nix/checks.nix ctx;
        apps = import ./nix/apps.nix ctx;
        legacyPackages.toolchain = ctx.toolchain;
        formatter = ctx.pkgs.nixpkgs-fmt;
      });
}
