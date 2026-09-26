{
  description = "tabular-center — transition-matrix state machines for Rust, Kotlin, and Swift";

  # The root flake composes three language flakes, one per implementation:
  #
  #   tabular-center-rust/flake.nix     checks, shell and apps for Rust
  #   tabular-center-kotlin/flake.nix   ... for Kotlin, plus the Gradle lock
  #   tabular-center-swift/flake.nix    ... for Swift, plus the SwiftPM lock
  #
  # Each is checkable on its own (`nix flake check ./tabular-center-rust`).
  # This one adds what no single language can check -- the steps that read
  # more than one implementation, `renderings-agree` above all -- and merges
  # the rest, so `nix flake check` here runs exactly the checks it always did,
  # under the same names.
  #
  # The language flakes are relative `path:` inputs, which needs Nix 2.26 or
  # later: older versions lock such an input as a separate copy of the
  # subdirectory, and the language flakes need the whole repository (they say
  # so, rather than failing on a missing file).
  #
  # Every input a language flake shares with this one `follows` it, so the
  # composed flake has one nixpkgs, one rust-overlay and one nixpkgs-swift, all
  # pinned by the flake.lock beside this file.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Swift only, and on its way out; see tabular-center-swift/flake.nix.
    # Declared here so the Swift flake can follow it and the pin stays in one
    # lock.
    nixpkgs-swift.url = "github:NixOS/nixpkgs/nixos-unstable";

    tabular-center-rust = {
      url = "path:./tabular-center-rust";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.rust-overlay.follows = "rust-overlay";
    };
    tabular-center-kotlin = {
      url = "path:./tabular-center-kotlin";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    tabular-center-swift = {
      url = "path:./tabular-center-swift";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-swift.follows = "nixpkgs-swift";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  # This file stays a table of contents. The cross-language checks, the
  # combined shell, and release and publication live in ./nix; each language's
  # toolchain lives in its own flake.
  outputs = { self, nixpkgs, flake-utils, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        langs = {
          rust = inputs.tabular-center-rust;
          kotlin = inputs.tabular-center-kotlin;
          swift = inputs.tabular-center-swift;
        };
        ctx = import ./nix/context.nix { inherit self system nixpkgs langs; };
        per = attr: nixpkgs.lib.foldl' (acc: l: acc // (l.${attr}.${system} or { })) { }
          (builtins.attrValues langs);
      in
      {
        # Each language's own shell under its name, and all three together as
        # the default.
        devShells = import ./nix/shells.nix ctx // {
          rust = langs.rust.devShells.${system}.default;
          kotlin = langs.kotlin.devShells.${system}.default;
          swift = langs.swift.devShells.${system}.default;
        };

        # Every language's checks, plus the ones that span languages. The
        # names do not collide: each language's are prefixed with it, and the
        # root's are the cross-language step names.
        checks = per "checks" // import ./nix/checks.nix ctx;

        # The language flakes' apps worth having at the root, by name, and the
        # root's own. The languages' `verify` and `default` are deliberately
        # not merged: at the root, `verify` means every step.
        apps = {
          inherit (langs.rust.apps.${system}) table-diff;
          inherit (langs.kotlin.apps.${system}) gradle-lock;
          inherit (langs.swift.apps.${system}) swift-lock;
        } // import ./nix/apps.nix ctx;

        # gradle-repo, swift-deps, swiftpm-plugin-support: inspectable
        # artifacts, not checks. See the language flakes for what each is.
        packages = per "packages";

        # `nix fmt` formats the flakes. Deliberately not a `nix flake check`: a
        # formatter version bump should not fail CI on a file nobody touched.
        formatter = ctx.pkgs.nixpkgs-fmt;
      });
}
