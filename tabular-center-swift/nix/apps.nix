# Runnable Swift entry points:
#
#   nix run .#swift-lock [-- --check]   resolve swift-syntax and write, or
#                                       verify, nix/swift-lock.json
#
# One of the repository's network commands (ARCHITECTURE.md 16). It runs
# inside the Swift dev shell, whose setup hooks nixpkgs' Swift depends on.
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

  swiftLock = pkgs.writeShellApplication {
    name = "tabular-center-swift-lock";
    runtimeInputs = [ pkgs.git ];
    text = ''
      ${cdRoot}
      exec nix develop "$PWD/tabular-center-swift" --command \
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
