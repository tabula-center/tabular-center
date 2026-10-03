# The Kotlin language flake: the core library, KSP processor, codegen and
# examples, with only the JDK, kotlinc, Gradle and ktlint in its closure.
#
#   nix flake check ./tabular-center-kotlin
#   nix run ./tabular-center-kotlin#gradle-lock [-- --check]
#   nix build ./tabular-center-kotlin#gradle-repo    the offline Maven repository
#
# Composed by the root flake, which makes these inputs follow its own. Needs
# the whole checkout, for spec/ and VERSION.
{
  description = "tabular-center, Kotlin implementation: core, KSP processor, and their checks";

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

        packages = ctx.lib.optionalAttrs (ctx.gradleRepo != null) {
          gradle-repo = ctx.gradleRepo;
        };

        legacyPackages.toolchain = ctx.toolchain;

        formatter = ctx.pkgs.nixpkgs-fmt;
      });
}
