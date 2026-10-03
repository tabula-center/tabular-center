# The Rust language flake: transition_matrix!, its examples and its checks,
# with only the Rust toolchain in its closure.
#
#   nix flake check ./tabular-center-rust
#   nix develop ./tabular-center-rust
#   nix run ./tabular-center-rust#bench
#
# Composed by the root flake, which makes these inputs follow its own. Needs
# the whole checkout, for spec/; legacyPackages.toolchain is what the root
# uses to put Rust into its own derivations.
{
  description = "tabular-center, Rust implementation: transition_matrix! and its checks";

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
        devShells = import ./nix/shells.nix ctx;
        checks = import ./nix/checks.nix ctx;
        apps = import ./nix/apps.nix ctx;

        legacyPackages.toolchain = ctx.toolchain;

        formatter = ctx.pkgs.nixpkgs-fmt;
      });
}
