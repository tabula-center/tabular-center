# The Rust toolchain and the check builder, per system. Threaded through the
# other modules in this directory as `ctx`.
{ self, system, nixpkgs, rust-overlay }:

let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ (import rust-overlay) ];
  };
  inherit (pkgs) lib;

  # What a check is given, each part its own store path.
  #
  # The checks run `tabular-center-rust/tools/verify` from a copy of the
  # repository's layout holding three things: this directory, spec/ (the
  # conformance contract, the one input all three languages share by design)
  # and .editorconfig. Each is copied into the store separately with
  # `builtins.path`, so each is hashed by its own contents -- and a check's
  # inputs are exactly those three and its toolchain. Editing Kotlin does not
  # rebuild a Rust check; editing spec/ rebuilds all three, as it should.
  #
  # It used to copy `self.sourceInfo` -- the whole checkout, one store path --
  # so every commit anywhere rebuilt every check, even after each check had
  # been trimmed to read only its own subtree. Reading less is what makes a
  # check independent; depending on less is what makes it cheap.
  #
  # `../../spec` reaches above this flake's directory. That works exactly when
  # the flake's source is the whole checkout: checked from git
  # (`nix flake check ./tabular-center-rust`, which nix treats as `?dir=`) or
  # composed by the root flake as a relative `path:` input (Nix 2.26 or later).
  # Asked first, through `self.sourceInfo`, so any other way in gets this
  # message rather than an "access to absolute path is forbidden" from
  # whichever file happened to be read first.
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
    conformance = builtins.pathExists ../tabula-conformance/Cargo.toml;
    examples = builtins.pathExists ../examples/Cargo.toml;
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
  # `tabular-center-rust/examples/05-iced` pulls winit and wgpu, and their build scripts look
  # for system libraries through pkg-config: fontconfig for text, xkbcommon and
  # the X11 set for input, wayland for the other display server. Vendoring the
  # crates does not supply these -- they are not crates -- so the GUI check
  # carries them.
  #
  # Only the GUI check does. Adding them to `rustInputs` would put an X11 stack
  # behind `cargo test` for the library, which has nothing to draw.
  #
  # Linux only. On macOS iced draws through Metal and AppKit, which come from
  # the Apple SDK the default stdenv already carries, and none of the list
  # below exists there: nixpkgs refuses to even EVALUATE `wayland` for Darwin,
  # and that one refusal took every Darwin check down with it, not just this
  # one. pkg-config stays on both -- it is a build tool, and harmless.
  #
  # The X11 libraries moved out of `xorg` (`xorg.libX11` -> `libx11`, and so
  # on) and the old names now warn. Written `new or old` so the pin can move in
  # either direction without an edit here.
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

  # crates.io dependencies of `tabular-center-rust/examples`, vendored from its Cargo.lock.
  #
  # Cargo writes a complete, hashed lock as a matter of course and nixpkgs'
  # `importCargoLock` consumes exactly that, so there is nothing to generate
  # and nothing to keep in step: the vendor directory is a function of the
  # committed lock. Empty today -- every example depends on the library by
  # path and nothing else -- so it passes vacuously.
  examplesVendor = pkgs.rustPlatform.importCargoLock {
    lockFile = ../examples/Cargo.lock;
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
    if builtins.pathExists ../examples/05-iced/Cargo.lock
    then pkgs.rustPlatform.importCargoLock { lockFile = ../examples/05-iced/Cargo.lock; }
    else null;

  rustStable = pkgs.rust-bin.stable.latest.default;

  # `runCommand` gives no writable HOME, and cargo wants one for its registry
  # cache even with zero dependencies. Every check is --offline --locked so it
  # can never silently reach the network.
  mkCheck = name: inputs: script:
    pkgs.runCommand "tabular-center-check-${name}"
      {
        nativeBuildInputs = commonInputs ++ inputs;
      }
      ''
        export HOME="$TMPDIR/home"
        export CARGO_HOME="$TMPDIR/cargo"

        # crates.io, replaced by the vendor directory built from
        # tabular-center-rust/examples/Cargo.lock.
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
        export TABULAR_CENTER_OFFLINE=1

        mkdir -p "$HOME"

        # This directory, spec/, and .editorconfig -- laid out as in the
        # repository, and nothing else. tools/verify runs from the repository
        # root and names paths from there, so the layout is kept; what is left
        # out is the other two languages and the root's own files. A step that
        # reached into either would fail here rather than quietly working,
        # which is what makes "independent" a checked property instead of a
        # claim. spec/ is the one thing all three share by design: it is the
        # cross-language contract.
        mkdir src
        cp -r ${specSrc} src/spec
        cp -r ${langSrc} src/tabular-center-rust
        cp ${editorconfig} src/.editorconfig
        chmod -R u+w src && cd src

        # Every script here starts `#!/usr/bin/env bash`, and the build
        # sandbox has no /usr/bin/env: on a strict sandbox (CI) the first step
        # died "bad interpreter", while a local nix with the sandbox relaxed
        # saw the host's /usr/bin/env and passed. patchShebangs points each
        # shebang at the store's bash -- the verify scripts, and every script
        # they call by path (compile-fail, the language scripts the root hands
        # steps to) -- so the check no longer depends on the host at all.
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
