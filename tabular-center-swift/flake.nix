{
  description = "tabular-center, Swift implementation: core, codegen, macro syntax, and their checks";

  # One of three language flakes, composed by the flake at the repository root.
  # Checkable on its own, with only the Swift toolchain in its closure:
  #
  #   nix flake check ./tabular-center-swift
  #
  # from a git checkout. Its examples are in ./examples; the one thing it needs
  # from outside this directory is spec/, the conformance contract, reached
  # through `self.sourceInfo` -- see nix/context.nix. The pins in flake.lock are the
  # root flake's, copied, and the root makes these inputs `follows` its own.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";

    # Swift only, and on its way out.
    #
    # It existed because nixos-25.05 shipped Swift 5.8, below the 5.9 macros
    # require. nixos-26.05 is newer, so `nixpkgs` should now carry a Swift that
    # can build macros/ -- specifically, a SwiftPM that ships
    # `CompilerPluginSupport`, which is what actually blocks that package. See
    # macros/README.md. Delete it once a Darwin run confirms
    # `./tools/verify swift-macros` passes on `nixpkgs` alone.
    nixpkgs-swift.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-swift, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        ctx = import ./nix/context.nix { inherit self system nixpkgs nixpkgs-swift; };
      in
      {
        devShells = import ./nix/shells.nix ctx;
        checks = import ./nix/checks.nix ctx;
        apps = import ./nix/apps.nix ctx;

        packages = ctx.lib.optionalAttrs (ctx.swiftDeps != null) {
          # The offline swift-syntax checkout set:
          #
          #   nix build ./tabular-center-swift#swift-deps
          #   ls result/checkouts
          #   cat result/workspace-state.json
          #
          # Worth being buildable on its own rather than only as a dependency
          # of `swift-macros`. The two values in `workspace-state.json` that
          # SwiftPM will silently reject -- the schema version and the checkout
          # directory name -- are inspectable here in one command, where inside
          # the check they surface as a re-resolve that dies offline.
          swift-deps = ctx.swiftDeps;
        }
        // ctx.lib.optionalAttrs (ctx.swiftpmPluginSupport != null) {
          # nixpkgs' SwiftPM with `CompilerPluginSupport` added:
          #
          #   nix build ./tabular-center-swift#swiftpm-plugin-support
          #   ls result/lib/swift/pm/ManifestAPI
          #
          # Build it through the flake: the same expression evaluated against
          # an ambient `<nixpkgs>` picks a different Swift with no cached build.
          swiftpm-plugin-support = ctx.swiftpmPluginSupport;
        };

        # For the root flake's combined shell and `renderings-agree`. See the
        # same output in ../tabular-center-rust/flake.nix.
        legacyPackages.toolchain = ctx.toolchain;

        formatter = ctx.pkgs.nixpkgs-fmt;
      });
}
