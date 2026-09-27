# The Swift half of `nix flake check`.
#
# Every check shells out to `tabular-center-swift/tools/verify <step>`, the
# same script `./tools/verify` at the root hands Swift steps to. The names are
# the ones the single root flake used.
ctx:

let
  inherit (ctx) lib swiftChecked swiftPkgs swiftSetup swiftDeps mkCheck;
  verify = name: mkCheck name swiftPkgs ''
    ${swiftSetup}
    ./tabular-center-swift/tools/verify ${name}
  '';
in
{
  # Runs on every platform, including the ones with no Swift toolchain, which
  # is the point: the risk it guards is a config file appearing in a commit,
  # and a commit can be made from anywhere. Text only.
  swift-format-config = mkCheck "swift-format-config" [ ]
    "./tabular-center-swift/tools/verify swift-format-config";
}
// lib.optionalAttrs (!swiftChecked) {
  # The Swift checks are NOT here, and this check exists to say so out loud.
  #
  # `lib.optionalAttrs` produces a smaller attribute set, and a smaller set of
  # checks is indistinguishable from a correct one in `nix flake check` output.
  # That is how `has.kotlin = pathExists ../kotlin/src` hid six checks for
  # months (PLAN 0c). Passing, not failing: the fix here is a Swift toolchain
  # nixpkgs does not package for this platform, so red would mean `nix flake
  # check` never passes on it no matter what anyone does.
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
  # Wherever a Swift toolchain exists, Linux included (ARCHITECTURE 13).
  swift = verify "swift";

  # swift-format comes from the same pin as swift itself, so this needed no
  # lock entry: the version question is answered by the pin that answers
  # Swift's.
  swift-matrix-stable = verify "swift-matrix-stable";
  swift-compile-fail = verify "swift-compile-fail";
  swift-conformance = verify "swift-conformance";
  swift-examples = verify "swift-examples";
  swift-codegen = verify "swift-codegen";

  # Reports whether this toolchain can declare a `.macro` target at all. Not a
  # pass/fail question -- no commit can change the answer -- so it prints and
  # succeeds, and the ledger carries it when the answer is no.
  swift-macro-support = verify "swift-macro-support";

  # The macro package. The pinned SwiftPM cannot declare a `.macro` target, so
  # this builds `TabularCenterMacroSyntax` against the offline swift-syntax checkout
  # set and skips, out loud, whatever still needs the plugin.
  swift-macros = mkCheck "swift-macros" swiftPkgs ''
    ${swiftSetup}
    ${lib.optionalString (swiftDeps != null) ''
      # The offline checkout set, exported rather than searched for: nix built
      # the directory and knows where it is.
      export TABULAR_CENTER_SWIFT_DEPS="${swiftDeps}"
    ''}
    ./tabular-center-swift/tools/verify swift-macros
  '';
}
