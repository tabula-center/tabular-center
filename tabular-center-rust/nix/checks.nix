# The Rust half of `nix flake check`.
#
# Every check shells out to `tabular-center-rust/tools/verify <step>`, the
# same script `./tools/verify` at the root hands Rust steps to. The names are
# the ones the single root flake used, so a composed `nix flake check` lists
# exactly the checks it always did.
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
  # The crate as crates.io would receive it, built from the archive alone.
  rust-package = verify "rust-package" "package" rustInputs;
  rust-compile-fail = verify "rust-compile-fail" "compile-fail" rustInputs;
  rust-asm-identical = verify "rust-asm-identical" "asm-identical" rustInputs;

  # The counterpart to kotlin-matrix-stable, and the reason it is separate from
  # rust-fmt: `cargo fmt --check` asserts the tree matches rustfmt's opinion,
  # which is a different question from whether rustfmt has an opinion about the
  # matrices at all. It does not today -- macro bodies are left alone -- and the
  # matrix files depend on that continuing to be true.
  rust-matrix-stable = verify "rust-matrix-stable" "rust-matrix-stable" rustInputs;
}
// lib.optionalAttrs has.conformance {
  rust-conformance = verify "rust-conformance" "conformance" rustInputs;
}
// lib.optionalAttrs has.examples {
  rust-examples = verify "rust-examples" "examples" rustInputs;

  # The GUI example: its own package, its own lock, and current stable rather
  # than the 1.75 the library is pinned to -- iced's tree needs edition 2024,
  # and the library's MSRV is not the place to pay for that.
  #
  # guiInputs because iced's build scripts look for fontconfig, xkbcommon, X11
  # and wayland through pkg-config, which vendoring crates cannot supply.
  rust-gui =
    if icedVendor != null
    then
      mkCheck "rust-gui" ([ rustStable ] ++ guiInputs) ''
        # Its own vendor directory, overriding the one mkCheck wrote.
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
