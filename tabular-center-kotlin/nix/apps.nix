# Runnable Kotlin entry points. Apps may touch the network and the working
# tree; checks may not.
ctx:

let
  inherit (ctx) pkgs commonInputs kotlinInputs jdkHome;

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
    name = "tabular-center-verify-kotlin";
    runtimeInputs = commonInputs ++ [ pkgs.git ] ++ kotlinInputs;
    text = ''
      ${cdRoot}
      # The pinned JDK for Gradle; see gradle_run in tools/verify.
      export JAVA_HOME="${jdkHome}"
      export TABULAR_CENTER_JDK_HOME="${jdkHome}"
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
    name = "tabular-center-gradle-lock";
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
      # The pinned JDK, and nothing else, for Gradle and its toolchains.
      #
      # An app runs on the host, not in the sandbox, so it inherits the host's
      # JAVA_HOME -- and GitHub's Ubuntu image sets that to its own Temurin 17.
      # Gradle ran on the 17 while `jvmToolchain(21)` compiled the KSP
      # processor with a 21, and loading it failed ("class file version
      # 65.0"). The checks were already pinned; this app was not, so it went
      # red on CI and green on a machine whose JAVA_HOME was unset.
      export JAVA_HOME="${jdkHome}"
      export TABULAR_CENTER_JDK_HOME="${jdkHome}"
      ./tabular-center-kotlin/tools/gradle-lock "$@"
    '';
  };
in
{
  verify = app verify "tabular-center-verify-kotlin"
    "Run the Kotlin steps of tools/verify, without the sandbox";

  gradle-lock = app gradleLock "tabular-center-gradle-lock"
    "Resolve the KSP examples against Maven and write tabular-center-kotlin/nix/gradle-lock.json";

  default = app verify "tabular-center-verify-kotlin" "Run the Kotlin checks";
}
