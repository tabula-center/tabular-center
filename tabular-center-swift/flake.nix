# The Swift language flake: the core library, codegen, macro syntax and
# examples, with only the Swift toolchain in its closure.
#
#   nix flake check ./tabular-center-swift
#   nix run ./tabular-center-swift#swift-lock [-- --check]
#   nix build ./tabular-center-swift#swift-deps               offline swift-syntax checkouts
#   nix build ./tabular-center-swift#swiftpm-plugin-support   SwiftPM with CompilerPluginSupport
#
# Composed by the root flake, which makes these inputs follow its own. Needs
# the whole checkout, for spec/.
{
  description = "tabular-center, Swift implementation: core, codegen, macro syntax, and their checks";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";

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
          swift-deps = ctx.swiftDeps;
        }
        // ctx.lib.optionalAttrs (ctx.swiftpmPluginSupport != null) {
          swiftpm-plugin-support = ctx.swiftpmPluginSupport;
        };

        legacyPackages.toolchain = ctx.toolchain;

        formatter = ctx.pkgs.nixpkgs-fmt;
      });
}
