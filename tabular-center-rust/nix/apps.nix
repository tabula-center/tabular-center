# Runnable Rust entry points, run from the repository root:
#
#   nix run .#table-diff [-- <fixture>]   render a fixture's matrix, diffed
#                                         against the generated table
#   nix run .#bench                       time matrix vs hand-written dispatch
#   nix run .#bench-asm                   compare them as assembly
ctx:

let
  inherit (ctx) pkgs commonInputs rustInputs;

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
      cargo run -q -p tabular-center-conformance --bin table-diff --offline --locked -- "$@"
    '';
  };
  bench = pkgs.writeShellApplication {
    name = "tabular-center-bench";
    runtimeInputs = commonInputs ++ [ pkgs.git ] ++ rustInputs;
    text = ''
      ${cdRoot}
      cd tabular-center-rust
      cargo bench -q -p tabular-center --bench dispatch --offline --locked
    '';
  };

  benchAsm = pkgs.writeShellApplication {
    name = "tabular-center-bench-asm";
    runtimeInputs = commonInputs ++ rustInputs ++ [
      pkgs.git
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnused
      pkgs.gnugrep
      pkgs.diffutils
    ];
    text = ''
      ${cdRoot}
      ./tabular-center-rust/tools/asm-diff
    '';
  };
in
{
  bench = app bench "tabular-center-bench"
    "Time matrix dispatch against hand-written dispatch";

  bench-asm = app benchAsm "tabular-center-bench-asm"
    "Diff the optimised assembly of matrix and hand-written dispatch";

  verify = app verify "tabular-center-verify-rust"
    "Run the Rust steps of tools/verify, without the sandbox";

  table-diff = app tableDiff "tabular-center-table-diff"
    "Render a machine's matrix as a diffable grid";

  default = app verify "tabular-center-verify-rust" "Run the Rust checks";
}
