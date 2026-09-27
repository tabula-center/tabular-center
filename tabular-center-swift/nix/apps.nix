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
  #
  # A launcher into the Swift dev shell, not an environment of its own. An app
  # gets a PATH and nothing else; a nix build and `nix develop` also run each
  # package's SETUP HOOKS, and nixpkgs' Swift toolchain depends on what they
  # export. Run bare, this app got a `swiftc` that answered
  # `-print-target-info` correctly when asked directly, and still handed
  # SwiftPM an empty answer -- "Failed to parse target info". The checks, and
  # the shell the committed lock was made in, run the hooks. So this runs
  # there too, rather than rebuilding their environment one guessed variable
  # at a time.
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
