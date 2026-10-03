# The Rust half of `nix flake check`: one check per
# `tabular-center-rust/tools/verify` step, named rust-<step>.
ctx:

let
  inherit (ctx) lib has rustInputs guiInputs icedVendor rustStable mkCheck;
  verify = check: step: inputs:
    mkCheck check inputs "./tabular-center-rust/tools/verify ${step}";
in
{
  rust-fmt = verify "rust-fmt" "fmt" rustInputs;
  rust-clippy = verify "rust-clippy" "clippy" rustInputs;
  rust-test = verify "rust-test" "test" rustInputs;
  rust-no-std = verify "rust-no-std" "no-std" rustInputs;
  rust-package = verify "rust-package" "package" rustInputs;
  rust-compile-fail = verify "rust-compile-fail" "compile-fail" rustInputs;
  rust-asm-identical = verify "rust-asm-identical" "asm-identical" rustInputs;

  rust-matrix-stable = verify "rust-matrix-stable" "rust-matrix-stable" rustInputs;
}
// lib.optionalAttrs has.conformance {
  rust-conformance = verify "rust-conformance" "conformance" rustInputs;
}
// lib.optionalAttrs has.examples {
  rust-examples = verify "rust-examples" "examples" rustInputs;

  rust-gui =
    if icedVendor != null
    then
      mkCheck "rust-gui" ([ rustStable ] ++ guiInputs) ''
        cat > "$CARGO_HOME/config.toml" <<VENDOR
        [source.crates-io]
        replace-with = "vendored-sources"

        [source.vendored-sources]
        directory = "${icedVendor}"
        VENDOR
        ./tabular-center-rust/tools/verify rust-gui
      ''
    else
      mkCheck "rust-gui" [ ] ''
        cat <<'MSG'
        rust-gui: tabular-center-rust/examples/05-iced/Cargo.lock does not exist, so there is
        no artifact set to build the GUI example against.

        Create it once, on a machine with network:

          cd tabular-center-rust/examples/05-iced && cargo generate-lockfile

        and commit it. Nix vendors from the lock after that.
        MSG
        exit 1
      '';
}
