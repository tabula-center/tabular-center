{
  description = "tabular-center, Kotlin implementation: core, KSP processor, and their checks";

  # One of three language flakes, composed by the flake at the repository root.
  # Checkable on its own, with only the JDK, kotlinc, Gradle and ktlint in its
  # closure:
  #
  #   nix flake check ./tabular-center-kotlin
  #
  # from a git checkout. spec/ and examples/kotlin are reached through
  # `self.sourceInfo`; see nix/context.nix. The pins in flake.lock are the
  # root flake's, copied, and the root makes these inputs `follows` its own.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        ctx = import ./nix/context.nix { inherit self system nixpkgs; };
      in
      {
        devShells = import ./nix/shells.nix ctx;
        checks = import ./nix/checks.nix ctx;
        apps = import ./nix/apps.nix ctx;

        # Not a check, and not built by `nix flake check`.
        #
        # The offline Maven repository the KSP checks resolve against, exposed
        # so it can be built and inspected on purpose:
        #
        #   nix build ./tabular-center-kotlin#gradle-repo
        #   ls result
        #
        # It reaches no network: every artifact is a `fetchurl` with a hash
        # pinned in nix/gradle-lock.json. Regenerating that lock is
        # tools/gradle-lock (`nix run .#gradle-lock`), which does need network
        # and is deliberately not a derivation -- see the header of that
        # script. Absent until the lock exists, so a fresh clone that has never
        # run the generator gets "attribute 'gradle-repo' missing" rather than
        # an evaluation error about a file that is not there.
        packages = ctx.lib.optionalAttrs (ctx.gradleRepo != null) {
          gradle-repo = ctx.gradleRepo;
        };

        # For the root flake's combined shell and `renderings-agree`. See the
        # same output in ../tabular-center-rust/flake.nix.
        legacyPackages.toolchain = ctx.toolchain;

        formatter = ctx.pkgs.nixpkgs-fmt;
      });
}
