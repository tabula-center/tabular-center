# Runnable Rust entry points. Apps may touch the working tree; checks may not.
ctx:

let
  inherit (ctx) pkgs commonInputs rustInputs;

  # Every app works on the checkout, so it starts at the repository root --
  # the same root tools/verify runs from.
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
    name = "tabular-center-verify-rust";
    runtimeInputs = commonInputs ++ [ pkgs.git ] ++ rustInputs;
    text = ''
      ${cdRoot}
      ./tabular-center-rust/tools/verify "$@"
    '';
  };

  tableDiff = pkgs.writeShellApplication {
    name = "tabular-center-table-diff";
    runtimeInputs = commonInputs ++ [ pkgs.git ] ++ rustInputs;
    text = ''
      ${cdRoot}
      cd tabular-center-rust
      cargo run -q -p tabula-conformance --bin table-diff --offline --locked -- "$@"
    '';
  };
in
{
  verify = app verify "tabular-center-verify-rust"
    "Run the Rust steps of tools/verify, without the sandbox";

  table-diff = app tableDiff "tabular-center-table-diff"
    "Render a machine's matrix as a diffable grid";

  default = app verify "tabular-center-verify-rust" "Run the Rust checks";
}
