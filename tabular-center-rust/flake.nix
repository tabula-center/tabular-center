{
  description = "tabular-center, Rust implementation: transition_matrix! and its checks";

  # One of three language flakes, composed by the flake at the repository root.
  # Checkable on its own, with only the Rust toolchain in its closure:
  #
  #   nix flake check ./tabular-center-rust
  #
  # from a git checkout. Its examples are in ./examples; the one thing it needs
  # from outside this directory is spec/, the conformance contract, reached
  # through `self.sourceInfo` -- see nix/context.nix.
  #
  # The pins in flake.lock are the root flake's, copied, and the root makes
  # every one of these inputs `follows` its own, so the two cannot disagree
  # about which Rust they built.
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

        # What the root flake needs to put Rust into a derivation of its own:
        # the combined dev shell and `renderings-agree`, which runs all three
        # languages at once. Exported rather than rebuilt at the root, so the
        # toolchain is declared in exactly one place. legacyPackages because
        # it is per-system and not a derivation; `nix flake check` does not
        # build what is in it.
        legacyPackages.toolchain = ctx.toolchain;

        formatter = ctx.pkgs.nixpkgs-fmt;
      });
}
