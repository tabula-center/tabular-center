{
  description = "tabula — transition-matrix state machines for Rust, Kotlin, and Swift";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # This file stays a table of contents. Toolchains, shells, checks, apps, and
  # publication live in ./nix, because a flake that grows past a screen stops
  # being read and starts being copied.
  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        ctx = import ./nix/context.nix { inherit self system nixpkgs rust-overlay; };
      in
      {
        devShells = import ./nix/shells.nix ctx;
        checks = import ./nix/checks.nix ctx;
        apps = import ./nix/apps.nix ctx;

        # `nix fmt` formats the flake. Deliberately not a `nix flake check`: a
        # formatter version bump should not fail CI on a file nobody touched.
        formatter = ctx.pkgs.nixpkgs-fmt;
      });
}
