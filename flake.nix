{
  description = "tabula — transition-matrix state machines for Rust, Kotlin, and Swift";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Swift only, and on its way out.
    #
    # It existed because nixos-25.05 shipped Swift 5.8, below the 5.9 macros
    # require. nixos-26.05 is newer, so the main input should now carry a Swift
    # that can build swift/macros -- specifically, a SwiftPM that ships
    # `CompilerPluginSupport`, which is what actually blocks that package. See
    # swift/macros/README.md.
    #
    # Kept pointing at unstable for one release rather than deleted in the same
    # commit as the bump. If 26.05's Swift turns out to lag again, the fallback
    # is `nixpkgs-swift.follows`-style surgery in nix/context.nix rather than
    # re-adding an input under pressure. Delete it once a Darwin run confirms
    # `./tools/verify swift-macros` passes on the main input alone.
    nixpkgs-swift.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  # This file stays a table of contents. Toolchains, shells, checks, apps, and
  # publication live in ./nix, because a flake that grows past a screen stops
  # being read and starts being copied.
  outputs = { self, nixpkgs, nixpkgs-swift, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        ctx = import ./nix/context.nix {
          inherit self system nixpkgs nixpkgs-swift rust-overlay;
        };
      in
      {
        devShells = import ./nix/shells.nix ctx;
        checks = import ./nix/checks.nix ctx;
        apps = import ./nix/apps.nix ctx;

        # Not a check, and not built by `nix flake check`.
        #
        # The offline Maven repository `kotlin-ksp` resolves against, exposed
        # so it can be built and inspected on purpose:
        #
        #   nix build .#gradle-repo
        #   ls result
        #
        # It reaches no network: every artifact is a `fetchurl` with a hash
        # pinned in nix/gradle-lock.json. Regenerating that lock is
        # `./tools/gradle-lock`, which does need network and is deliberately
        # not a derivation -- see the header of that script for why the
        # fixed-output derivation this replaces was the wrong shape.
        #
        # Absent until the lock exists, so a fresh clone that has never run
        # the generator gets "attribute 'gradle-repo' missing" rather than an
        # evaluation error about a file that is not there.
        packages = ctx.lib.optionalAttrs (ctx.gradleRepo != null) {
          gradle-repo = ctx.gradleRepo;
        };

        # `nix fmt` formats the flake. Deliberately not a `nix flake check`: a
        # formatter version bump should not fail CI on a file nobody touched.
        formatter = ctx.pkgs.nixpkgs-fmt;
      });
}
