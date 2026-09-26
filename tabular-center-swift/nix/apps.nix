# Runnable Swift entry points. Apps may touch the network and the working
# tree; checks may not.
ctx:

let
  inherit (ctx) pkgs lib commonInputs swiftPkgs swiftSetup swiftChecked;

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
    name = "tabular-center-verify-swift";
    runtimeInputs = commonInputs ++ [ pkgs.git ] ++ lib.optionals swiftChecked swiftPkgs;
    text = ''
      ${cdRoot}
      ${swiftSetup}
      ./tabular-center-swift/tools/verify "$@"
    '';
  };

  # The second and last command in the repository that reaches the network.
  # See the header of tools/swift-lock, and the Kotlin flake's gradle-lock for
  # the same shape against Maven.
  swiftLock = pkgs.writeShellApplication {
    name = "tabular-center-swift-lock";
    runtimeInputs = commonInputs ++ swiftPkgs ++ [
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
      ${swiftSetup}
      ./tabular-center-swift/tools/swift-lock "$@"
    '';
  };
in
{
  verify = app verify "tabular-center-verify-swift"
    "Run the Swift steps of tools/verify, without the sandbox";

  swift-lock = app swiftLock "tabular-center-swift-lock"
    "Resolve tabular-center-swift/macros against the network and write tabular-center-swift/nix/swift-lock.json";

  default = app verify "tabular-center-verify-swift" "Run the Swift checks";
}
