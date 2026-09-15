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
    swiftLibraryPath gradleRepo mkCheck;
  verify = name: inputs: mkCheck name inputs "./tools/verify ${name}";
in
{
  version = verify "version" [ ];

  # docs/ is generated from spec/. Checked in CI because the pages are what
  # diagnostic messages link to: a stale tree means someone following a link
  # from an error reads about a different error.
  docs = verify "docs" [ ];
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
  # Guards the matrix alignment against ktlint's formatter -- narrowly, without
  # adopting ktlint as a style gate. See the backlog entry in PLAN.md.
  kotlin-matrix-stable = verify "kotlin-matrix-stable" kotlinInputs;
}
// lib.optionalAttrs has.kotlin {
  # The annotation processor, running.
  #
  # Its own check rather than part of `kotlin-examples`, because it is the one
  # Kotlin step whose inputs are not just source: it needs the artifact set
  # nix/gradle-lock.json pins. A failure here means a stale lock or a broken
  # processor, and burying that in the examples step would make it read as an
  # example being broken.
  #
  # Gated on `has.kotlin` ALONE, deliberately -- not on the lock existing.
  #
  # Gating on the lock was the obvious thing and it was wrong in the same way
  # `has.kotlin = pathExists ../kotlin/src` was wrong: a check that is absent
  # from the attribute set cannot report that it is absent. `nix flake check`
  # would have printed a tidy green summary over a KSP example nobody built,
  # which is the failure this repository has now hit twice. Once is a bug;
  # twice is a pattern worth spending a check on.
  #
  # So when there is no lock, this check EXISTS and FAILS, with the command
  # that fixes it. The experiment is reproducible or it is red; it is never
  # quietly smaller than it looks.
  kotlin-ksp =
    if gradleRepo != null
    then
      mkCheck "kotlin-ksp" kotlinInputs ''
        # Exported here rather than guessed at by the script, for the same
        # reason swiftLibraryPath is: nix built the directory and knows where
        # it is. Everything else about the step is `tools/verify`'s, so the
        # no-nix path runs the same commands against the real repositories.
        export TABULA_MAVEN_REPO="${gradleRepo}"
        ./tools/verify kotlin-ksp
      ''
    else
      mkCheck "kotlin-ksp" [ ] ''
        cat <<'MSG'
        kotlin-ksp: nix/gradle-lock.json does not exist, so there is no
        artifact set to build examples/kotlin/06-generated against.

        Bootstrap it once, on a machine with network:

            nix run .#gradle-lock

        then commit nix/gradle-lock.json. After that every `nix flake check`
        builds the KSP example offline against pinned hashes -- nix fetches
        each artifact itself, which is reproducible in a way a Gradle
        resolution inside a sandbox is not.

        This check fails rather than disappearing on purpose. A missing check
        looks exactly like a passing one in `nix flake check` output, and that
        is how the Kotlin steps went unrun for as long as they did.
        MSG
        exit 1
      '';
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

  swift-codegen = mkCheck "swift-codegen" swiftPkgs ''
    export LD_LIBRARY_PATH="${swiftLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ./tools/verify swift-codegen
  '';

  # The macro package. Expected to skip rather than pass: the sandbox has no
  # network, and the pinned SwiftPM cannot declare a `.macro` target at all.
  # It is a check anyway so the skip is printed by CI instead of being
  # something a developer discovers by running `swift build` in the wrong
  # directory and reading a manifest error.
  swift-macros = mkCheck "swift-macros" swiftPkgs ''
    export LD_LIBRARY_PATH="${swiftLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ./tools/verify swift-macros
  '';
}
