# Everything the other modules share: package set, toolchains, and the two
# builders. Imported once per system and threaded through as `ctx`.
{ self, system, nixpkgs, rust-overlay }:

let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ (import rust-overlay) ];
  };

  inherit (pkgs) lib stdenv;

  # Phases land one language at a time, so nothing may be declared for a
  # directory that is not there. Gate on the build file rather than the
  # directory: a stub created early in a phase should not switch checks on
  # before the tooling can actually run.
  has = {
    kotlin = builtins.pathExists ../kotlin/src;
    kotlinGradle = builtins.pathExists ../kotlin/settings.gradle.kts;
    swift = builtins.pathExists ../swift/Package.swift;
    rustConformance = builtins.pathExists ../rust/tabula-conformance/Cargo.toml;
    examples = builtins.pathExists ../examples/rust/Cargo.toml;
  };

  rustToolchain =
    if builtins.pathExists ../rust/rust-toolchain.toml
    then pkgs.rust-bin.fromRustupToolchainFile ../rust/rust-toolchain.toml
    else
      pkgs.rust-bin.stable."1.75.0".default.override {
        extensions = [ "rust-src" "rust-analyzer" "clippy" "rustfmt" ];
        targets = [ "thumbv7em-none-eabihf" ];
      };

  jdk = pkgs.jdk21;

  # Swift is first-class on Darwin. On Linux nixpkgs' swift lags and macro
  # plugins are toolchain-version sensitive, so treat the Linux path as
  # best-effort. See ARCHITECTURE.md section 13.
  swiftAvailable = stdenv.isDarwin || builtins.hasAttr "swift" pkgs;

  swiftPkgs = lib.optionals swiftAvailable (
    [ pkgs.swift ]
    ++ lib.optionals (builtins.hasAttr "swiftpm" pkgs) [ pkgs.swiftpm ]
    ++ lib.optionals (builtins.hasAttr "swift-format" pkgs) [ pkgs.swift-format ]
  );

  rustInputs = [ rustToolchain pkgs.cargo-expand pkgs.cargo-nextest ];
  kotlinInputs = [ jdk pkgs.gradle pkgs.kotlin pkgs.ktlint ];
  commonInputs = [ pkgs.git pkgs.jq pkgs.just pkgs.graphviz pkgs.nixpkgs-fmt ];

  # `runCommand` gives no writable HOME, and cargo wants one for its registry
  # cache even with zero dependencies. Every check is --offline --locked so it
  # can never silently reach the network.
  mkCheck = name: inputs: script:
    pkgs.runCommand "tabula-check-${name}"
      { nativeBuildInputs = commonInputs ++ inputs; }
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

in
{
  inherit
    self system pkgs lib has
    rustToolchain jdk swiftAvailable swiftPkgs
    rustInputs kotlinInputs commonInputs
    mkCheck mkShell;
}
