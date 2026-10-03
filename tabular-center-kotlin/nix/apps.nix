# Runnable Kotlin entry points:
#
#   nix run .#gradle-lock [-- --check]   resolve the Gradle builds and write,
#                                        or verify, nix/gradle-lock.json
#
# One of the two commands in the repository that reach the network; it runs
# with the pinned Gradle and JDK so the lock records what the checks replay.
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
      export JAVA_HOME="${jdkHome}"
      export TABULAR_CENTER_JDK_HOME="${jdkHome}"
      ./tabular-center-kotlin/tools/verify "$@"
    '';
  };

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
