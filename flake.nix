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
        ## What exists yet
        ##
        ## Phases land one language at a time, so the flake must not declare
        ## checks for directories that are not there. An earlier version did,
        ## and `nix flake check` died on `cd kotlin: No such file or
        ## directory` before reaching the Rust checks.
        ##
        ## Gate on the build file rather than the directory: a stub `kotlin/`
        ## created early in Phase 4 should not switch the checks on before
        ## Gradle can actually run.
        ##########################################################

        hasKotlin = builtins.pathExists ./kotlin/settings.gradle.kts;
        hasSwift = builtins.pathExists ./swift/Package.swift;
        hasRustConformance = builtins.pathExists ./rust/tabula-conformance/Cargo.toml;

        ##########################################################
        ## Toolchains
        ##########################################################

        rustToolchain =
          if builtins.pathExists ./rust/rust-toolchain.toml
          then pkgs.rust-bin.fromRustupToolchainFile ./rust/rust-toolchain.toml
          else
            pkgs.rust-bin.stable."1.75.0".default.override {
              extensions = [ "rust-src" "rust-analyzer" "clippy" "rustfmt" ];
              targets = [ "thumbv7em-none-eabihf" ];
            };

        jdk = pkgs.jdk21;

        # Swift is first-class on Darwin. On Linux nixpkgs' swift lags and
        # macro plugins are toolchain-version sensitive, so the Swift shell is
        # best-effort there. See ARCHITECTURE.md section 13.
        swiftAvailable = stdenv.isDarwin || builtins.hasAttr "swift" pkgs;

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
          pkgs.jq
          pkgs.just
          pkgs.graphviz
          pkgs.nixpkgs-fmt
        ];

        mkShell = name: extra: pkgs.mkShell {
          inherit name;
          packages = commonInputs ++ extra;

          JAVA_HOME = "${jdk}";
          GRADLE_USER_HOME = "./.gradle-home";

          shellHook = ''
            echo "tabula :: ${name}"
            ${lib.optionalString (!swiftAvailable) ''
              echo "  note: no swift toolchain on ${system}; swift/ is skipped."
            ''}
          '';
        };

        ##########################################################
        ## Checks
        ##
        ## `runCommand` gives no writable HOME, and cargo wants one for its
        ## registry cache even with zero dependencies. Point HOME and
        ## CARGO_HOME at the build directory, and pin --offline --locked so a
        ## check can never silently reach the network.
        ##########################################################

        mkCheck = name: inputs: script:
          pkgs.runCommand "tabula-check-${name}"
            {
              nativeBuildInputs = commonInputs ++ inputs;
            }
            ''
              export HOME="$TMPDIR/home"
              export CARGO_HOME="$TMPDIR/cargo"
              export GRADLE_USER_HOME="$TMPDIR/gradle"
              export CARGO_NET_OFFLINE=true
              mkdir -p "$HOME" "$CARGO_HOME" "$GRADLE_USER_HOME"

              cp -r ${self} src && chmod -R u+w src && cd src
              ${script}
              touch $out
            '';

        cargo = args: "cd rust && cargo ${args} --offline --locked";

      in
      {
        ##########################################################
        ## Dev shells
        ##########################################################

        devShells = {
          default = mkShell "all" (rustInputs ++ kotlinInputs ++ swiftPkgs);
          rust = mkShell "rust" rustInputs;
          kotlin = mkShell "kotlin" kotlinInputs;
          swift = mkShell "swift" swiftPkgs;
        };

        ##########################################################
        ## Checks — `nix flake check`
        ##########################################################

        checks = {
          rust-fmt = mkCheck "rust-fmt" rustInputs ''
            cd rust && cargo fmt --all -- --check
          '';

          rust-clippy = mkCheck "rust-clippy" rustInputs ''
            ${cargo "clippy --all-targets --all-features"} -- -D warnings
          '';

          rust-test = mkCheck "rust-test" rustInputs ''
            ${cargo "nextest run --all-features"}
          '';

          # Phase 1 exit criterion: the core must build without std.
          rust-no-std = mkCheck "rust-no-std" rustInputs ''
            ${cargo "build -p tabula --no-default-features --target thumbv7em-none-eabihf"}
          '';

          # Every diagnostic in spec/diagnostics.md has a fixture that must
          # fail to compile with the expected message.
          rust-compile-fail = mkCheck "rust-compile-fail" rustInputs ''
            ./tools/compile-fail
          '';
        }
        // lib.optionalAttrs hasRustConformance {
          rust-conformance = mkCheck "rust-conformance" rustInputs ''
            ${cargo "run -q -p tabula-conformance"}
          '';
        }
        // lib.optionalAttrs hasKotlin {
          kotlin-test = mkCheck "kotlin-test" kotlinInputs ''
            cd kotlin && gradle --offline --no-daemon test
          '';

          # Guards the zero-runtime-dependency rule. See ARCHITECTURE 11.2.
          kotlin-no-runtime-deps = mkCheck "kotlin-no-runtime-deps" kotlinInputs ''
            cd kotlin
            gradle --offline --no-daemon :tabula-core:dependencies \
              --configuration runtimeClasspath > deps.txt
            if grep -qE 'kotlinx|org\.jetbrains\.compose' deps.txt; then
              echo "tabula-core acquired a runtime dependency:"; cat deps.txt; exit 1
            fi
          '';
        }
        // lib.optionalAttrs (hasSwift && swiftAvailable) {
          swift-test = mkCheck "swift-test" swiftPkgs ''
            cd swift && swift test
          '';
        };

        ##########################################################
        ## Apps
        ##########################################################

        apps =
          let
            conformance = pkgs.writeShellApplication {
              name = "tabula-conformance";
              runtimeInputs = commonInputs ++ rustInputs
                ++ lib.optionals hasKotlin kotlinInputs
                ++ lib.optionals (hasSwift && swiftAvailable) swiftPkgs;
              text = ''
                ${lib.optionalString hasRustConformance ''
                  echo "== rust =="
                  (cd rust && cargo run -p tabula-conformance --offline --locked)
                ''}
                ${lib.optionalString hasKotlin ''
                  echo "== kotlin =="
                  (cd kotlin && gradle --no-daemon :tabula-conformance:run)
                ''}
                ${lib.optionalString (hasSwift && swiftAvailable) ''
                  echo "== swift =="
                  (cd swift && swift test --filter Conformance)
                ''}
                ${lib.optionalString
                  (!hasRustConformance && !hasKotlin && !(hasSwift && swiftAvailable)) ''
                  echo "no conformance harness has landed yet (phase 3)."
                ''}
              '';
            };

            tableDiff = pkgs.writeShellApplication {
              name = "tabula-table-diff";
              runtimeInputs = commonInputs ++ rustInputs;
              text = ''
                cd rust
                cargo run -p tabula-conformance --bin table-diff --offline --locked -- "$@"
              '';
            };
          in
          {
            conformance = {
              type = "app";
              program = "${conformance}/bin/tabula-conformance";
              meta.description = "Run every implementation against spec/conformance";
            };

            table-diff = {
              type = "app";
              program = "${tableDiff}/bin/tabula-table-diff";
              meta.description = "Render a machine's matrix as a diffable grid";
            };

            default = self.apps.${system}.conformance;
          };

        # `nix fmt` formats the flake. Deliberately NOT a `nix flake check`:
        # a formatter version bump would then fail CI on a file nobody touched,
        # which trains people to ignore check failures.
        formatter = pkgs.nixpkgs-fmt;
      });
}
