# Runnable entry points.
#
# Split from the checks because they do different things: a check must be
# hermetic and offline, while an app is allowed to touch the network, the git
# index, and a registry token. Keeping them in one file invited confusing one
# for the other.
ctx:

let
  inherit (ctx) pkgs lib has rustInputs kotlinInputs swiftPkgs swiftAvailable commonInputs;

  app = drv: name: description: {
    type = "app";
    program = "${drv}/bin/${name}";
    meta.description = description;
  };

  conformance = pkgs.writeShellApplication {
    name = "tabula-conformance";
    runtimeInputs = commonInputs ++ rustInputs
      ++ lib.optionals has.kotlin kotlinInputs
      ++ lib.optionals (has.swift && swiftAvailable) swiftPkgs;
    text = ''
      ${lib.optionalString has.rustConformance ''
        echo "== rust =="
        ./tools/verify conformance
      ''}
      ${lib.optionalString has.kotlin ''
        echo "== kotlin =="
        ./tools/verify kotlin-conformance
      ''}
      ${lib.optionalString (has.swift && swiftAvailable) ''
        echo "== swift =="
        ./tools/verify swift
      ''}
    '';
  };

  tableDiff = pkgs.writeShellApplication {
    name = "tabula-table-diff";
    runtimeInputs = commonInputs ++ rustInputs;
    text = ''
      cd rust
      cargo run -q -p tabula-conformance --bin table-diff --offline --locked -- "$@"
    '';
  };

  verify = pkgs.writeShellApplication {
    name = "tabula-verify";
    runtimeInputs = commonInputs ++ rustInputs
      ++ lib.optionals has.kotlin kotlinInputs
      ++ lib.optionals (has.swift && swiftAvailable) swiftPkgs;
    text = ''./tools/verify "$@"'';
  };

  publish = import ./publish.nix ctx;

in
{
  conformance = app conformance "tabula-conformance"
    "Run every implementation against spec/conformance";

  table-diff = app tableDiff "tabula-table-diff"
    "Render a machine's matrix as a diffable grid";

  verify = app verify "tabula-verify"
    "Run the same checks nix flake check runs, without the sandbox";

  release = app publish.release "tabula-release"
    "Set the version everywhere, verify, and tag";

  publish = app publish.publish "tabula-publish"
    "Publish every language's package (dry run unless --execute)";

  default = app verify "tabula-verify" "Run the checks";
}
