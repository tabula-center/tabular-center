# `nix run .#tb-fmt` aligns the matrices in the checkout; with `-- --check`
# it reports what would change and exits non-zero.
ctx:

let
  inherit (ctx) pkgs commonInputs rustToolchain;
  tbFmt = pkgs.writeShellApplication {
    name = "tabular-center-tb-fmt";
    runtimeInputs = commonInputs ++ [ rustToolchain ];
    text = ''
      root="$(git rev-parse --show-toplevel)"
      cargo run -q --release --offline --locked \
        --manifest-path "$root/tabular-center-fmt/Cargo.toml" -- "$@"
    '';
  };
  app = {
    type = "app";
    program = "${tbFmt}/bin/tabular-center-tb-fmt";
    meta.description = "Align the cells of every .tb. matrix file (-- --check to report only)";
  };
in
{
  tb-fmt = app;
  default = app;
}
