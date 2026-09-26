# What the root modules share: a package set for the cross-language checks,
# the three language toolchains as their flakes export them, and the builders.
# Imported once per system and threaded through as `ctx`.
{ self, system, nixpkgs, langs }:

let
  pkgs = import nixpkgs { inherit system; };
  inherit (pkgs) lib;

  # Each language flake's `legacyPackages.<system>.toolchain`:
  #   { inputs; env; setup; available; }
  # A toolchain is declared once, in its own flake; the root only combines.
  toolchains = lib.mapAttrs (_: l: l.legacyPackages.${system}.toolchain) langs;

  allInputs = lib.concatMap (t: t.inputs) (builtins.attrValues toolchains);
  allEnv = lib.foldl' (acc: t: acc // t.env) { } (builtins.attrValues toolchains);
  allSetup = lib.concatMapStringsSep "\n" (t: t.setup) (builtins.attrValues toolchains);

  has = {
    # Read by nix/publish.nix only: Maven publication needs a Gradle build the
    # library does not have yet (RELEASING.md), and ARCHITECTURE 12 says it
    # will not get one. No check gates on this.
    kotlinGradle = builtins.pathExists ../tabular-center-kotlin/settings.gradle.kts;
  };

  commonInputs = [ pkgs.git pkgs.jq pkgs.just pkgs.graphviz pkgs.nixpkgs-fmt ];

  # The root's checks are text-only except `renderings-agree`, which takes
  # every toolchain and every toolchain's environment. `env` is merged into
  # the derivation for all of them: it is only variables (JAVA_HOME, NIX_CC),
  # and one builder is simpler than two that differ by an attribute set.
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
        ${script}
        touch $out
      '';

  mkShell = name: extra: env: pkgs.mkShell ({
    inherit name;
    packages = commonInputs ++ extra;
    GRADLE_USER_HOME = "./.gradle-home";
    shellHook = ''
      echo "tabular-center :: ${name}"
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
