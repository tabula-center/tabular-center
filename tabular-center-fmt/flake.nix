{
  description = "tabular-center-fmt: aligns the cells of .tb. matrix files";

  # The fourth flake, beside the three implementations and composed by the
  # root the same way. It belongs to the `.tb.` format, not to a language
  # (spec/tabular-center-fmt.md), so it is not inside any of theirs, and it
  # checks on its own with nothing but a Rust toolchain:
  #
  #   nix flake check ./tabular-center-fmt
  #
  # Unlike the language flakes it needs nothing from outside its directory --
  # not even spec/ -- so its checks copy only this directory.
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
        # For the root flake, like the language flakes' -- see
        # ../tabular-center-rust/flake.nix.
        legacyPackages.toolchain = ctx.toolchain;
        formatter = ctx.pkgs.nixpkgs-fmt;
      });
}
