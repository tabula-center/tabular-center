# The Swift half of `nix flake check`: one check per
# `tabular-center-swift/tools/verify` step, named swift-<step>, wherever a
# Swift toolchain exists. Where none does, `swift-unavailable` passes and says
# so, rather than the checks quietly vanishing.
ctx:

let
  inherit (ctx) lib swiftChecked swiftPkgs swiftSetup swiftDeps mkCheck;
  verify = name: mkCheck name swiftPkgs ''
    ${swiftSetup}
    ./tabular-center-swift/tools/verify ${name}
  '';
in
{
  swift-format-config = mkCheck "swift-format-config" [ ]
    "./tabular-center-swift/tools/verify swift-format-config";
}
// lib.optionalAttrs (!swiftChecked) {
  swift-unavailable = mkCheck "swift-unavailable" [ ] ''
    cat <<'MSG'
    skip swift, swift-matrix-stable, swift-compile-fail, swift-conformance,
         swift-examples, swift-codegen, swift-macro-support, swift-macros
         (no Swift toolchain on this platform: nixpkgs has no `swift` for it,
         so these eight checks are absent from `nix flake check` rather than
         failing)

    They are not unchecked: ci.yml's check-darwin job runs all eight on macOS,
    and `nix develop .#swift` plus `./tools/verify swift` runs them here if a
    toolchain is installed by hand.
    MSG
  '';
}
// lib.optionalAttrs swiftChecked {
  swift = verify "swift";
  swift-standalone = verify "swift-standalone";

  swift-matrix-stable = verify "swift-matrix-stable";
  swift-compile-fail = verify "swift-compile-fail";
  swift-conformance = verify "swift-conformance";
  swift-examples = verify "swift-examples";
  swift-codegen = verify "swift-codegen";

  swift-macro-support = verify "swift-macro-support";

  swift-macros = mkCheck "swift-macros" swiftPkgs ''
    ${swiftSetup}
    ${lib.optionalString (swiftDeps != null) ''
      export TABULAR_CENTER_SWIFT_DEPS="${swiftDeps}"
    ''}
    ./tabular-center-swift/tools/verify swift-macros
  '';
}
