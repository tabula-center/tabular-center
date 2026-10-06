# The Rust toolchains and the check builder, per system, threaded through
# this directory as `ctx`. A check sees this directory, spec/ and
# .editorconfig, laid out as in the repository, with the examples' crates
# vendored from their Cargo.lock; the GUI check also gets iced's system
# libraries and current stable. ARCHITECTURE.md 16, "Nix".
{ self, system, nixpkgs, rust-overlay }:

let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ (import rust-overlay) ];
  };
  inherit (pkgs) lib;

  wholeCheckout = builtins.pathExists (self.sourceInfo.outPath + "/spec/conformance");
  fromCheckout = path:
    if wholeCheckout
    then path
    else
      throw ''
        tabular-center-rust: this flake's source is not the whole repository,
        so spec/ is out of reach. Check it from a git checkout
        (`nix flake check ./tabular-center-rust`), or through the root flake,
        with Nix 2.26 or later.
      '';

  specSrc = builtins.path { path = fromCheckout ../../spec; name = "tabular-center-spec"; };
  editorconfig = builtins.path { path = fromCheckout ../../.editorconfig; name = "tabular-center-editorconfig"; };
  langSrc = builtins.path { path = ./..; name = "tabular-center-rust-src"; };

  has = {
    conformance = builtins.pathExists ../tabular-center-conformance/Cargo.toml;
    examples = builtins.pathExists ../examples/Cargo.toml;
  };

  rustToolchain =
    if builtins.pathExists ../rust-toolchain.toml
    then pkgs.rust-bin.fromRustupToolchainFile ../rust-toolchain.toml
    else
      pkgs.rust-bin.stable."1.94.0".default.override {
        extensions = [ "rust-src" "rust-analyzer" "clippy" "rustfmt" ];
        targets = [ "thumbv7em-none-eabihf" ];
      };

  rustInputs = [ rustToolchain pkgs.cargo-expand pkgs.cargo-nextest ];

  guiInputs = [ pkgs.pkg-config ] ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    pkgs.fontconfig
    pkgs.libxkbcommon
    pkgs.wayland
    pkgs.libGL
    pkgs.vulkan-loader
    (pkgs.libx11 or pkgs.xorg.libX11)
    (pkgs.libxcursor or pkgs.xorg.libXcursor)
    (pkgs.libxi or pkgs.xorg.libXi)
    (pkgs.libxrandr or pkgs.xorg.libXrandr)
  ];

  commonInputs = [ pkgs.git pkgs.jq pkgs.just pkgs.graphviz pkgs.nixpkgs-fmt ];

  examplesVendor = pkgs.rustPlatform.importCargoLock {
    lockFile = ../examples/Cargo.lock;
  };

  icedVendor =
    if builtins.pathExists ../examples/05-iced/Cargo.lock
    then pkgs.rustPlatform.importCargoLock { lockFile = ../examples/05-iced/Cargo.lock; }
    else null;

  rustStable = pkgs.rust-bin.stable.latest.default;

  mkCheck = name: inputs: script:
    pkgs.runCommand "tabular-center-check-${name}"
      {
        nativeBuildInputs = commonInputs ++ inputs;
      }
      ''
        export HOME="$TMPDIR/home"
        export CARGO_HOME="$TMPDIR/cargo"

        mkdir -p "$CARGO_HOME"
        cat > "$CARGO_HOME/config.toml" <<VENDOR
        [source.crates-io]
        replace-with = "vendored-sources"

        [source.vendored-sources]
        directory = "${examplesVendor}"
        VENDOR
        export CARGO_NET_OFFLINE=true

        export TABULAR_CENTER_OFFLINE=1

        mkdir -p "$HOME"

        mkdir src
        cp -r ${specSrc} src/spec
        cp -r ${langSrc} src/tabular-center-rust
        cp ${editorconfig} src/.editorconfig
        chmod -R u+w src && cd src

        patchShebangs --build . >/dev/null
        ${script}
        touch $out
      '';

  mkShell = name: extra: pkgs.mkShell {
    inherit name;
    packages = commonInputs ++ extra;
    shellHook = ''
      echo "tabular-center :: ${name}"
    '';
  };

in
{
  inherit self system pkgs lib has specSrc langSrc editorconfig rustToolchain rustInputs guiInputs
    commonInputs icedVendor rustStable mkCheck mkShell;

  toolchain = {
    inputs = rustInputs;
    env = { };
    setup = "";
    available = true;
  };
}
