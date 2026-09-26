# The Rust toolchain and the check builder, per system. Threaded through the
# other modules in this directory as `ctx`.
{ self, system, nixpkgs, rust-overlay }:

let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ (import rust-overlay) ];
  };
  inherit (pkgs) lib;

  # The whole repository, not just this directory.
  #
  # The checks run `tabular-center-rust/tools/verify` from the repository
  # root, because the conformance fixtures are in spec/ and the example
  # projects in examples/rust -- shared with the other two languages, so they
  # cannot live here. `self.outPath` is this directory; `self.sourceInfo` is
  # the source tree it was found in, which is the whole checkout both when
  # this flake is checked on its own from git (`?dir=`) and when the root
  # flake composes it through a relative `path:` input (Nix 2.26 or later).
  #
  # Checked rather than assumed. Pointed at with `path:./tabular-center-rust`
  # on the command line, or composed by a Nix older than 2.26, the source is
  # this directory alone, and every check would die later on a missing
  # spec/conformance with nothing to say about why.
  root =
    let r = self.sourceInfo.outPath; in
    if builtins.pathExists (r + "/spec/conformance")
    then r
    else
      throw ''
        tabular-center-rust: this flake's source is not the whole repository,
        so spec/ and examples/ are out of reach. Check it from a git checkout
        (`nix flake check ./tabular-center-rust`), or through the root flake,
        with Nix 2.26 or later.
      '';

  has = {
    conformance = builtins.pathExists ../tabula-conformance/Cargo.toml;
    examples = builtins.pathExists (root + "/examples/rust/Cargo.toml");
  };

  rustToolchain =
    if builtins.pathExists ../rust-toolchain.toml
    then pkgs.rust-bin.fromRustupToolchainFile ../rust-toolchain.toml
    else
      pkgs.rust-bin.stable."1.75.0".default.override {
        extensions = [ "rust-src" "rust-analyzer" "clippy" "rustfmt" ];
        targets = [ "thumbv7em-none-eabihf" ];
      };

  rustInputs = [ rustToolchain pkgs.cargo-expand pkgs.cargo-nextest ];

  # What iced needs to BUILD, which is more than what cargo vendors.
  #
  # `examples/rust/05-iced` pulls winit and wgpu, and their build scripts look
  # for system libraries through pkg-config: fontconfig for text, xkbcommon and
  # the X11 set for input, wayland for the other display server. Vendoring the
  # crates does not supply these -- they are not crates -- so the GUI check
  # carries them.
  #
  # Only the GUI check does. Adding them to `rustInputs` would put an X11 stack
  # behind `cargo test` for the library, which has nothing to draw.
  guiInputs = [
    pkgs.pkg-config
    pkgs.fontconfig
    pkgs.libxkbcommon
    pkgs.wayland
    pkgs.libGL
    pkgs.vulkan-loader
    pkgs.xorg.libX11
    pkgs.xorg.libXcursor
    pkgs.xorg.libXi
    pkgs.xorg.libXrandr
  ];

  commonInputs = [ pkgs.git pkgs.jq pkgs.just pkgs.graphviz pkgs.nixpkgs-fmt ];

  # crates.io dependencies of `examples/rust`, vendored from its Cargo.lock.
  #
  # Cargo writes a complete, hashed lock as a matter of course and nixpkgs'
  # `importCargoLock` consumes exactly that, so there is nothing to generate
  # and nothing to keep in step: the vendor directory is a function of the
  # committed lock. Empty today -- every example depends on the library by
  # path and nothing else -- so it passes vacuously.
  examplesVendor = pkgs.rustPlatform.importCargoLock {
    lockFile = root + "/examples/rust/Cargo.lock";
  };

  # The GUI example's own lock, and its own toolchain.
  #
  # iced's tree needs edition 2024, which the pinned 1.75 cannot parse. That
  # pin is the library's MSRV and worth keeping exactly where it is: on the
  # library and on the four examples that depend on nothing else. This one
  # package gets current stable instead, which is what an application would
  # use. Null until the lock exists: `importCargoLock` on a missing file fails
  # at EVALUATION, which would take the whole flake down rather than one check.
  icedVendor =
    if builtins.pathExists (root + "/examples/rust/05-iced/Cargo.lock")
    then pkgs.rustPlatform.importCargoLock { lockFile = root + "/examples/rust/05-iced/Cargo.lock"; }
    else null;

  rustStable = pkgs.rust-bin.stable.latest.default;

  # `runCommand` gives no writable HOME, and cargo wants one for its registry
  # cache even with zero dependencies. Every check is --offline --locked so it
  # can never silently reach the network.
  mkCheck = name: inputs: script:
    pkgs.runCommand "tabula-check-${name}"
      {
        nativeBuildInputs = commonInputs ++ inputs;
      }
      ''
        export HOME="$TMPDIR/home"
        export CARGO_HOME="$TMPDIR/cargo"

        # crates.io, replaced by the vendor directory built from
        # examples/rust/Cargo.lock.
        #
        # Here rather than in the one check that "needs" it: `clippy` resolves
        # the examples workspace too, and so does anything else that runs cargo
        # outside tabular-center-rust/. Wiring it per check meant listing which
        # ones touch cargo, and that list was wrong the first time -- clippy
        # failed with "no matching package named `iced`" while the examples
        # check was fine.
        mkdir -p "$CARGO_HOME"
        cat > "$CARGO_HOME/config.toml" <<VENDOR
        [source.crates-io]
        replace-with = "vendored-sources"

        [source.vendored-sources]
        directory = "${examplesVendor}"
        VENDOR
        export CARGO_NET_OFFLINE=true

        # The sandbox has no network, and a step that needs one must SKIP
        # rather than fail. Stated, not detected; tools/verify reads it.
        export TABULA_OFFLINE=1

        mkdir -p "$HOME"

        cp -r ${root} src && chmod -R u+w src && cd src
        ${script}
        touch $out
      '';

  mkShell = name: extra: pkgs.mkShell {
    inherit name;
    packages = commonInputs ++ extra;
    shellHook = ''
      echo "tabula :: ${name}"
    '';
  };

in
{
  inherit self system pkgs lib has root rustToolchain rustInputs guiInputs
    commonInputs icedVendor rustStable mkCheck mkShell;

  # For the root flake. See `legacyPackages` in ../flake.nix.
  toolchain = {
    inputs = rustInputs;
    # Exported variables a derivation using this toolchain must set, and shell
    # to run before any step. Rust needs neither; the keys are here so the
    # root can treat all three languages alike.
    env = { };
    setup = "";
    available = true;
  };
}
