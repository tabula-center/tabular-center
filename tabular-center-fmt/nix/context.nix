# The formatter's toolchain and check builder. Threaded through the other
# modules in this directory as `ctx`.
{ self, system, nixpkgs, rust-overlay }:

let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ (import rust-overlay) ];
  };
  inherit (pkgs) lib;

  rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ../rust-toolchain.toml;
  commonInputs = [ pkgs.git pkgs.nixpkgs-fmt ];

  # This directory, alone, under its own name: the formatter reads nothing
  # outside it, so a change anywhere else rebuilds none of its checks.
  src = builtins.path { path = ./..; name = "tabular-center-fmt-src"; };

  mkCheck = name: script:
    pkgs.runCommand "tabular-center-check-${name}"
      { nativeBuildInputs = commonInputs ++ [ rustToolchain ]; }
      ''
        export HOME="$TMPDIR/home"
        export CARGO_HOME="$TMPDIR/cargo"
        export CARGO_NET_OFFLINE=true
        export TABULAR_CENTER_OFFLINE=1
        mkdir -p "$HOME" "$CARGO_HOME" src
        cp -r ${src} src/tabular-center-fmt
        chmod -R u+w src && cd src
        # See the note in ../../tabular-center-rust/nix/context.nix: the
        # sandbox has no /usr/bin/env.
        patchShebangs --build . >/dev/null
        ${script}
        touch $out
      '';
in
{
  inherit self system pkgs lib rustToolchain commonInputs mkCheck;

  mkShell = pkgs.mkShell {
    name = "tabular-center-fmt";
    packages = commonInputs ++ [ rustToolchain ];
    shellHook = ''echo "tabular-center :: fmt"'';
  };

  # For the root flake. See `legacyPackages` in ../flake.nix.
  toolchain = {
    inputs = [ rustToolchain ];
    env = { };
    setup = "";
    available = true;
  };
}
