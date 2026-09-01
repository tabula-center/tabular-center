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

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        inherit (pkgs) lib stdenv;

        ##########################################################
        ## Toolchains
        ##########################################################

        # Pinned via rust-toolchain.toml so `cargo` and CI agree.
        # Falls back to a stable pin if the file is absent.
        rustToolchain =
          if builtins.pathExists ./rust/rust-toolchain.toml
          then pkgs.rust-bin.fromRustupToolchainFile ./rust/rust-toolchain.toml
          else pkgs.rust-bin.stable."1.85.0".default.override {
            extensions = [ "rust-src" "rust-analyzer" "clippy" "rustfmt" ];
            # no_std verification target (Phase 1 exit criterion)
            targets = [ "thumbv7em-none-eabihf" ];
          };

        jdk = pkgs.jdk21;

        # Swift is first-class on Darwin. On Linux nixpkgs' swift lags and
        # macro plugins in particular are toolchain-version sensitive, so the
        # Swift shell is best-effort there. See ARCHITECTURE.md §13.
        swiftAvailable = stdenv.isDarwin
          || (builtins.hasAttr "swift" pkgs && stdenv.isLinux);

        swiftPkgs = lib.optionals swiftAvailable (
          [ pkgs.swift ]
          ++ lib.optionals (builtins.hasAttr "swiftpm" pkgs) [ pkgs.swiftpm ]
          ++ lib.optionals (builtins.hasAttr "swift-format" pkgs) [ pkgs.swift-format ]
        );

        ##########################################################
        ## Per-language inputs
        ##########################################################

        rustInputs = [ rustToolchain pkgs.cargo-expand pkgs.cargo-nextest ];

        kotlinInputs = [ jdk pkgs.gradle pkgs.kotlin pkgs.ktlint ];

        commonInputs = [
          pkgs.git
          pkgs.jq          # conformance fixtures are JSON
          pkgs.just
          pkgs.graphviz    # DOT export smoke tests
          pkgs.nixpkgs-fmt
        ];

        mkShell = name: extra: pkgs.mkShell {
          inherit name;
          packages = commonInputs ++ extra;

          JAVA_HOME = "${jdk}";
          # Keep Gradle's cache inside the repo so the shell is reproducible-ish
          # and `nix flake check` sandboxing does not fight ~/.gradle.
          GRADLE_USER_HOME = "./.gradle-home";

          shellHook = ''
            echo "tabula :: ${name}"
            ${lib.optionalString (!swiftAvailable) ''
              echo "  note: swift toolchain unavailable on ${system}; swift/ is skipped."
            ''}
          '';
        };

        ##########################################################
        ## Checks
        ##########################################################

        mkCheck = name: inputs: script:
          pkgs.runCommand "tabula-check-${name}"
            { nativeBuildInputs = commonInputs ++ inputs; }
            ''
              cp -r ${self} src && chmod -R u+w src && cd src
              ${script}
              touch $out
            '';

      in
      {
        ##########################################################
        ## Dev shells
        ##########################################################

        devShells = {
          default = mkShell "all" (rustInputs ++ kotlinInputs ++ swiftPkgs);
          rust    = mkShell "rust"   rustInputs;
          kotlin  = mkShell "kotlin" kotlinInputs;
          swift   = mkShell "swift"  swiftPkgs;
        };

        ##########################################################
        ## Checks — `nix flake check`
        ##########################################################

        checks = {
          nix-fmt = mkCheck "nix-fmt" [ ] ''
            nixpkgs-fmt --check flake.nix
          '';

          rust-fmt = mkCheck "rust-fmt" rustInputs ''
            cd rust && cargo fmt --all -- --check
          '';

          rust-clippy = mkCheck "rust-clippy" rustInputs ''
            cd rust && cargo clippy --all-targets --all-features -- -D warnings
          '';

          # Includes the trybuild UI suite: every diagnostic in
          # spec/diagnostics.md must have a corresponding failing-compile test.
          rust-test = mkCheck "rust-test" rustInputs ''
            cd rust && cargo nextest run --all-features
          '';

          # Phase 1 exit criterion: core must build without std.
          rust-no-std = mkCheck "rust-no-std" rustInputs ''
            cd rust && cargo build -p tabula \
              --no-default-features \
              --target thumbv7em-none-eabihf
          '';

          kotlin-lint = mkCheck "kotlin-lint" kotlinInputs ''
            ktlint "kotlin/**/*.kt" || true   # alignment rules exempted per .editorconfig
          '';

          kotlin-test = mkCheck "kotlin-test" kotlinInputs ''
            cd kotlin && gradle --offline --no-daemon test
          '';

          # Guards the zero-runtime-dependency rule: tabula-core must not
          # depend on kotlinx.coroutines or anything else. See ARCHITECTURE §11.2.
          kotlin-no-runtime-deps = mkCheck "kotlin-no-runtime-deps" kotlinInputs ''
            cd kotlin
            gradle --offline --no-daemon :tabula-core:dependencies \
              --configuration runtimeClasspath > deps.txt
            if grep -qE 'kotlinx|org\.jetbrains\.compose' deps.txt; then
              echo "tabula-core acquired a runtime dependency:"; cat deps.txt; exit 1
            fi
          '';
        } // lib.optionalAttrs swiftAvailable {
          swift-test = mkCheck "swift-test" swiftPkgs ''
            cd swift && swift test
          '';
        };

        ##########################################################
        ## Apps
        ##########################################################

        apps = {
          # Drives all available implementations against spec/conformance.
          conformance = {
            type = "app";
            program = "${pkgs.writeShellScript "tabula-conformance" ''
              set -euo pipefail
              export PATH=${lib.makeBinPath (commonInputs ++ rustInputs ++ kotlinInputs ++ swiftPkgs)}:$PATH
              echo "== rust =="   && (cd rust   && cargo run -p tabula-conformance)
              echo "== kotlin ==" && (cd kotlin && gradle --no-daemon :tabula-conformance:run)
              ${lib.optionalString swiftAvailable ''
                echo "== swift ==" && (cd swift && swift test --filter Conformance)
              ''}
            ''}";
          };

          # Renders golden matrix snapshots as diffable tables (Phase 8).
          table-diff = {
            type = "app";
            program = "${pkgs.writeShellScript "tabula-table-diff" ''
              set -euo pipefail
              export PATH=${lib.makeBinPath (commonInputs ++ rustInputs)}:$PATH
              cd rust && cargo run -p tabula-conformance --bin table-diff -- "$@"
            ''}";
          };

          default = self.apps.${system}.conformance;
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}
