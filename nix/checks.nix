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
    swiftLibraryPath gradleRepo swiftDeps examplesVendor guiInputs
    icedVendor rustStable mkCheck;
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

  # The counterpart to kotlin-matrix-stable, and the reason it is separate from
  # rust-fmt: `cargo fmt --check` asserts the tree matches rustfmt's opinion,
  # which is a different question from whether rustfmt has an opinion about the
  # matrices at all. It does not today -- macro bodies are left alone -- and 28
  # files depend on that continuing to be true.
  rust-matrix-stable = verify "rust-matrix-stable" rustInputs;

  # The check above the other two. Both of those scan roots they name, so a
  # matrix in a directory neither names is outside both and silently so. This
  # enumerates the files that exist and asks which scan reaches each, which is
  # the question a scan cannot ask about itself.
  #
  # No toolchain: it is `find` and `case`. Which is also why it can run on
  # every platform while the language checks it guards cannot.
  matrix-covered = verify "matrix-covered" [ ];

  # Runs on every platform, including the ones with no Swift toolchain, which
  # is the point: the risk it guards is a config file appearing in a commit,
  # and a commit can be made from anywhere. Tying it to `swiftChecked` would
  # have left the guard absent on exactly the machines most likely to add one
  # without being able to run it.
  swift-format-config = verify "swift-format-config" [ ];

  # The first check that compares all three implementations to each other
  # rather than each to a golden. Needs no toolchain -- it reads source as
  # text -- which is why it can run on every platform and notice a Swift
  # diagnostic going missing on a machine that cannot build Swift.
  diagnostics-coverage = verify "diagnostics-coverage" [ ];

  # Asks the conformance harness's question earlier. That harness walks
  # adapters, so an incomplete fixture is invisible until one exists -- and
  # every fixture here has been added a patch or more ahead of its adapters.
  fixtures-complete = verify "fixtures-complete" [ ];

  # The one check that must see more than one implementation at a time: the
  # renderings are not committed, so agreement is asserted by rendering from
  # each toolchain present and diffing. Rust and Kotlin are always here;
  # Swift joins where it exists. It fails rather than passes if fewer than
  # two are present, so it cannot agree with itself.
  renderings-agree =
    let
      swiftEnv = lib.optionalString swiftChecked
        ''export LD_LIBRARY_PATH="${swiftLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"'';
    in
    mkCheck "renderings-agree"
      (rustInputs ++ kotlinInputs ++ lib.optionals swiftChecked swiftPkgs) ''
        ${swiftEnv}
        ./tools/verify renderings-agree
      '';

  # tools/verify only compares. A step that can bless passes by construction,
  # which is what swift-codegen's TABULA_BLESS briefly made it. Text only.
  no-bless = verify "no-bless" [ ];

  # Generated code is not committed, as source or as a golden: emitted source
  # is compiled and compared at check time instead. Text only.
  no-generated = verify "no-generated" [ ];

  # CONTRIBUTING says every diagnostic gets a fixture. Text only, and now a
  # check rather than a habit.
  diagnostics-tested = verify "diagnostics-tested" [ ];
}
// lib.optionalAttrs has.rustConformance {
  rust-conformance = verify "conformance" rustInputs;
}
// lib.optionalAttrs has.examples {
  rust-examples = verify "examples" rustInputs;

  # The GUI example: its own package, its own lock, and current stable rather
  # than the 1.75 the rest of this repository is pinned to -- iced's tree needs
  # edition 2024, and tabula's MSRV is not the place to pay for that.
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
        ./tools/verify rust-gui
      ''
    else
      mkCheck "rust-gui" [ ] ''
        cat <<'MSG'
        rust-gui: examples/rust/05-iced/Cargo.lock does not exist, so there is
        no artifact set to build the GUI example against.

        Create it once, on a machine with network:

          cd examples/rust/05-iced && cargo generate-lockfile

        and commit it. Nix vendors from the lock after that.
        MSG
        exit 1
      '';
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
  kotlin-ksp-incremental =
    if gradleRepo != null
    then
      mkCheck "kotlin-ksp-incremental" kotlinInputs ''
        export TABULA_MAVEN_REPO="${gradleRepo}"
        ./tools/verify kotlin-ksp-incremental
      ''
    else
      mkCheck "kotlin-ksp-incremental" [ ] ''
        echo "kotlin-ksp-incremental: needs nix/gradle-lock.json; see kotlin-ksp"
        exit 1
      '';

  kotlin-ksp-compile-fail =
    if gradleRepo != null
    then
      mkCheck "kotlin-ksp-compile-fail" kotlinInputs ''
        export TABULA_MAVEN_REPO="${gradleRepo}"
        ./tools/verify kotlin-ksp-compile-fail
      ''
    else
      mkCheck "kotlin-ksp-compile-fail" [ ] ''
        echo "kotlin-ksp-compile-fail: needs nix/gradle-lock.json; see kotlin-ksp"
        exit 1
      '';

  # The Compose Desktop example. Same wiring as kotlin-ksp; the step itself
  # skips, loudly, when the locked artifact set predates Compose.
  kotlin-compose =
    if gradleRepo != null
    then
      mkCheck "kotlin-compose" kotlinInputs ''
        export TABULA_MAVEN_REPO="${gradleRepo}"
        ./tools/verify kotlin-compose
      ''
    else
      mkCheck "kotlin-compose" [ ] ''
        echo "kotlin-compose: needs nix/gradle-lock.json; see kotlin-ksp"
        exit 1
      '';

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
// lib.optionalAttrs (has.swift && !swiftChecked) {
  # The Swift checks are NOT here, and this check exists to say so out loud.
  #
  # `lib.optionalAttrs` produces a smaller attribute set, and a smaller set of
  # checks is indistinguishable from a correct one in `nix flake check` output.
  # That is exactly how `has.kotlin = pathExists ../kotlin/src` hid six checks
  # for months (0c), and how `kotlin-ksp` would have hidden itself had it been
  # gated on the lock (0d). Six Swift checks vanish on Linux for a reason that
  # is real, and the reason being real does not make their absence visible.
  #
  # Passing, not failing. `kotlin-ksp` is red without its lock because the fix
  # is one command the user can run; here the fix is a Swift toolchain that
  # nixpkgs does not package for this platform, so red would mean `nix flake
  # check` never passes on Linux no matter what anyone does. A check that
  # cannot go green is not a signal, it is noise with a red light.
  #
  # `skip ` prefixed so it reads the same as every other skip in the repo, and
  # so a future run that greps the build log finds it the way `tools/verify`
  # greps its tally.
  swift-unavailable = mkCheck "swift-unavailable" [ ] ''
    cat <<'MSG'
    skip swift, swift-compile-fail, swift-conformance, swift-codegen,
         swift-examples, swift-macros (no Swift toolchain on this platform:
         nixpkgs has no `swift` for it, so these six checks are absent from
         `nix flake check` rather than failing)

    They are not unchecked: ci.yml's check-darwin job runs all six on macOS,
    and `nix develop .#swift` plus `./tools/verify swift` runs them here if a
    toolchain is installed by hand.
    MSG
  '';
}
// lib.optionalAttrs (has.swift && swiftChecked) {
  # Wherever a Swift toolchain exists, Linux included: `swiftChecked` is
  # `swiftAvailable` (see context.nix and ARCHITECTURE 13).
  #
  # The runtime path is exported here rather than left to the script, for the
  # same reason as the dev shell: nix knows where the libraries are and the
  # script would be guessing.
  swift = mkCheck "swift" swiftPkgs ''
    export LD_LIBRARY_PATH="${swiftLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ./tools/verify swift
  '';

  # swift-format comes from the same pin as swift itself (context.nix), so
  # this needed no lock entry: the version question is answered by the pin
  # that answers Swift's.
  swift-matrix-stable = mkCheck "swift-matrix-stable" swiftPkgs ''
    export LD_LIBRARY_PATH="${swiftLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ./tools/verify swift-matrix-stable
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

  # Reports whether this toolchain can declare a `.macro` target at all. Not a
  # pass/fail question -- no commit can change the answer -- so it prints and
  # succeeds, and the ledger carries it when the answer is no.
  swift-macro-support = verify "swift-macro-support" swiftPkgs;

  # The macro package. The pinned SwiftPM cannot declare a `.macro` target, so
  # this builds `TabulaMacroSyntax` against the offline swift-syntax checkout
  # set and skips, out loud, whatever still needs the plugin.
  swift-macros = mkCheck "swift-macros" swiftPkgs ''
    export LD_LIBRARY_PATH="${swiftLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    ${lib.optionalString (swiftDeps != null) ''
      # The offline checkout set, exported rather than searched for -- same
      # reason as TABULA_MAVEN_REPO and swiftLibraryPath: nix built the
      # directory and knows where it is.
      export TABULA_SWIFT_DEPS="${swiftDeps}"
    ''}
    ./tools/verify swift-macros
  '';
}
