# Runnable Kotlin entry points. Apps may touch the network and the working
# tree; checks may not.
ctx:

let
  inherit (ctx) pkgs commonInputs kotlinInputs;

  cdRoot = ''
    if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
      cd "$root"
    else
      echo "not inside a git checkout of tabular-center; these apps work on the tree" >&2
      exit 1
    fi
  '';

  app = drv: name: description: {
    type = "app";
    program = "${drv}/bin/${name}";
    meta.description = description;
  };

  verify = pkgs.writeShellApplication {
    name = "tabula-verify-kotlin";
    runtimeInputs = commonInputs ++ [ pkgs.git ] ++ kotlinInputs;
    text = ''
      ${cdRoot}
      ./tabular-center-kotlin/tools/verify "$@"
    '';
  };

  # The one command in the repository that is allowed to reach Maven.
  #
  # An app and not a check: a check must be hermetic, and this is a bootstrap.
  # It resolves the KSP examples against real repositories and writes
  # tabular-center-kotlin/nix/gradle-lock.json, which is then committed and
  # consumed by nix/gradle-repo.nix as ordinary `fetchurl` calls.
  #
  # Run through the flake rather than as a bare script so the gradle, jdk and
  # curl doing the resolving are the pinned ones -- the same gradle `kotlin-ksp`
  # replays against, since kotlinInputs supplies both. The shell utilities are
  # listed because `writeShellApplication` PREPENDS runtimeInputs to PATH, and
  # on macOS the fallback is BSD `find` and `sed`.
  gradleLock = pkgs.writeShellApplication {
    name = "tabula-gradle-lock";
    runtimeInputs = commonInputs ++ kotlinInputs ++ [
      pkgs.git
      pkgs.curl
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnused
      pkgs.gnugrep
      pkgs.diffutils
    ];
    text = ''
      ${cdRoot}
      ./tabular-center-kotlin/tools/gradle-lock "$@"
    '';
  };
in
{
  verify = app verify "tabula-verify-kotlin"
    "Run the Kotlin steps of tools/verify, without the sandbox";

  gradle-lock = app gradleLock "tabula-gradle-lock"
    "Resolve the KSP examples against Maven and write tabular-center-kotlin/nix/gradle-lock.json";

  default = app verify "tabula-verify-kotlin" "Run the Kotlin checks";
}
