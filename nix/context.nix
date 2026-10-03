# What the root modules share, imported once per system as `ctx`: a package
# set for the cross-language checks, each language's toolchain as its flake
# exports it ({ inputs; env; setup; available; }), and mkCheck, which runs one
# tools/verify step over the whole checkout.
{ self, system, nixpkgs, langs }:

let
  pkgs = import nixpkgs { inherit system; };
  inherit (pkgs) lib;

  toolchains = lib.mapAttrs (_: l: l.legacyPackages.${system}.toolchain) langs;

  allInputs = lib.concatMap (t: t.inputs) (builtins.attrValues toolchains);
  allEnv = lib.foldl' (acc: t: acc // t.env) { } (builtins.attrValues toolchains);
  allSetup = lib.concatMapStringsSep "\n" (t: t.setup) (builtins.attrValues toolchains);

  has = {
    kotlinGradle = builtins.pathExists ../tabular-center-kotlin/settings.gradle.kts;
  };

  commonInputs = [ pkgs.git pkgs.jq pkgs.just pkgs.graphviz pkgs.nixpkgs-fmt ];

  mkCheck = name: inputs: script:
    pkgs.runCommand "tabular-center-check-${name}"
      ({
        nativeBuildInputs = commonInputs ++ inputs;
      } // allEnv)
      ''
        export HOME="$TMPDIR/home"
        export CARGO_HOME="$TMPDIR/cargo"
        export GRADLE_USER_HOME="$TMPDIR/gradle"
        export CARGO_NET_OFFLINE=true
        export TABULAR_CENTER_OFFLINE=1
        mkdir -p "$HOME" "$CARGO_HOME" "$GRADLE_USER_HOME"

        cp -r ${self} src && chmod -R u+w src && cd src

        patchShebangs --build . >/dev/null
        ${script}
        touch $out
      '';

  mkShell = name: extra: env: pkgs.mkShell ({
    inherit name;
    packages = commonInputs ++ extra;
    shellHook = ''
      echo "tabular-center :: ${name}"
      export GRADLE_USER_HOME="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/tabular-center-kotlin/.gradle-home"
      ${lib.optionalString (!toolchains.swift.available) ''
        echo "  note: no swift toolchain on ${system}; tabular-center-swift/ is skipped."
      ''}
      echo "  one language only: nix develop .#rust / .#kotlin / .#swift"
    '';
  } // env);

in
{
  inherit self system pkgs lib has toolchains allInputs allEnv allSetup
    commonInputs mkCheck mkShell;
}
