# `nix flake check`.
#
# Every check shells out to `tools/verify <step>`. That script is the single
# source of truth for what "green" means, so the flake, CI, and a developer
# typing `./tools/verify` all run the same commands. Three lint escapes reached
# CI because the local loop and the flake checked different things; a
# duplicated list here is how that happens.
ctx:

let
  inherit (ctx) lib has rustInputs kotlinInputs swiftPkgs swiftChecked
    swiftLibraryPath mkCheck;
  verify = name: inputs: mkCheck name inputs "./tools/verify ${name}";
in
{
  version = verify "version" [ ];
  rust-fmt = verify "fmt" rustInputs;
  rust-clippy = verify "clippy" rustInputs;
  rust-test = verify "test" rustInputs;
  rust-no-std = verify "no-std" rustInputs;
  rust-compile-fail = verify "compile-fail" rustInputs;
}
// lib.optionalAttrs has.rustConformance {
  rust-conformance = verify "conformance" rustInputs;
}
// lib.optionalAttrs has.examples {
  rust-examples = verify "examples" rustInputs;
}
// lib.optionalAttrs has.kotlin {
  kotlin = verify "kotlin" kotlinInputs;
  kotlin-compile-fail = verify "kotlin-compile-fail" kotlinInputs;
  kotlin-conformance = verify "kotlin-conformance" kotlinInputs;
  kotlin-codegen = verify "kotlin-codegen" kotlinInputs;
  kotlin-examples = verify "kotlin-examples" kotlinInputs;
}
// lib.optionalAttrs has.kotlinGradle {
  # Guards the zero-runtime-dependency rule. Only meaningful once Gradle can
  # resolve; until then the rule is enforced by kotlinc seeing no classpath but
  # the stdlib. See ARCHITECTURE 11.2.
  kotlin-no-runtime-deps = mkCheck "kotlin-no-runtime-deps" kotlinInputs ''
    cd kotlin
    gradle --offline --no-daemon :tabula-core:dependencies \
      --configuration runtimeClasspath > deps.txt
    if grep -qE 'kotlinx|org[.]jetbrains[.]compose' deps.txt; then
      echo "tabula-core acquired a runtime dependency:"; cat deps.txt; exit 1
    fi
  '';
}
// lib.optionalAttrs (has.swift && swiftChecked) {
  # Darwin only. See the note on `swiftChecked` in context.nix: on Linux this
  # is `nix develop .#swift` followed by `./tools/verify swift`.
  #
  # The runtime path is exported here rather than left to the script, for the
  # same reason as the dev shell: nix knows where the libraries are and the
  # script would be guessing.
  swift = mkCheck "swift" swiftPkgs ''
    export LD_LIBRARY_PATH="${swiftLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ./tools/verify swift
  '';

  swift-compile-fail = mkCheck "swift-compile-fail" swiftPkgs ''
    export LD_LIBRARY_PATH="${swiftLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ./tools/verify swift-compile-fail
  '';

  swift-conformance = mkCheck "swift-conformance" swiftPkgs ''
    export LD_LIBRARY_PATH="${swiftLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ./tools/verify swift-conformance
  '';

  swift-examples = mkCheck "swift-examples" swiftPkgs ''
    export LD_LIBRARY_PATH="${swiftLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ./tools/verify swift-examples
  '';
}
