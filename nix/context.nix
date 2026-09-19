# Everything the other modules share: package set, toolchains, and the two
# builders. Imported once per system and threaded through as `ctx`.
{ self, system, nixpkgs, nixpkgs-swift, rust-overlay }:

let
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ (import rust-overlay) ];
  };

  # Swift comes from its own input: the pinned nixpkgs has 5.8, below the 5.9
  # macros require. Keeping it separate means chasing a Swift toolchain never
  # moves the Rust or Kotlin ones.
  swiftPkgsSet = import nixpkgs-swift { inherit system; };

  inherit (pkgs) lib stdenv;

  # Phases land one language at a time, so nothing may be declared for a
  # directory that is not there. Gate on the build file rather than the
  # directory: a stub created early in a phase should not switch checks on
  # before the tooling can actually run.
  #
  # Kotlin has no build file, deliberately -- kotlinc is driven directly, so
  # that the zero-runtime-dependency rule holds by construction rather than by
  # a dependency report (ARCHITECTURE 11.2, 12). So the gate is the core source
  # every Kotlin step compiles first.
  #
  # It used to read `../kotlin/src`, a directory this tree has never had. The
  # gate was therefore always false and `nix flake check` silently ran NONE of
  # the six Kotlin checks -- while `tools/verify` ran them all, and ci.yml's
  # `check` job runs only the flake. Three paths, one definition of green, and
  # a whole language missing from two of them because a path was wrong by one
  # word. A gate that names a path which does not exist cannot report that it
  # is off; that is what makes this class of bug expensive.
  has = {
    kotlin = builtins.pathExists ../kotlin/core/dev/tabula/Step.kt;
    # Read by nix/publish.nix only: Maven publication needs a Gradle build the
    # library does not have yet (RELEASING.md). No CHECK gates on this -- the
    # zero-runtime-dependency rule is enforced by the `kotlin` step compiling
    # tabula-core against an empty classpath, not by a dependency report.
    kotlinGradle = builtins.pathExists ../kotlin/settings.gradle.kts;
    swift = builtins.pathExists ../swift/Package.swift;
    rustConformance = builtins.pathExists ../rust/tabula-conformance/Cargo.toml;
    examples = builtins.pathExists ../examples/rust/Cargo.toml;

    # The KSP example can build offline exactly when the lock exists. Gating on
    # the lock rather than on `gradle` being installed is the whole point of
    # the rewrite: gradle is always present in these checks -- kotlinInputs
    # ships it -- and what was ever missing is the artifacts.
    gradleLock = builtins.pathExists ../nix/gradle-lock.json;

    # Same gate, same reasoning, for SwiftPM. `swift/macros` is the only thing
    # in the repository that links a remote package.
    swiftLock = builtins.pathExists ../nix/swift-lock.json;
  };

  # The offline Maven repository, or null when nothing has been locked yet.
  gradleRepo =
    if has.gradleLock
    then import ./gradle-repo.nix { inherit pkgs lib; lockFile = ../nix/gradle-lock.json; }
    else null;

  # nixpkgs' SwiftPM with `CompilerPluginSupport` added. See the header of
  # that file; null where there is no Swift to augment.
  swiftpmPluginSupport =
    if swiftAvailable && builtins.hasAttr "swiftpm" swiftPkgsSet
    then
      import ./swiftpm-plugin-support.nix {
        inherit pkgs lib swiftPkgsSet;
      }
    else null;

  swiftDeps =
    if has.swiftLock
    then import ./swift-deps.nix { inherit pkgs lib; lockFile = ../nix/swift-lock.json; }
    else null;

  rustToolchain =
    if builtins.pathExists ../rust/rust-toolchain.toml
    then pkgs.rust-bin.fromRustupToolchainFile ../rust/rust-toolchain.toml
    else
      pkgs.rust-bin.stable."1.75.0".default.override {
        extensions = [ "rust-src" "rust-analyzer" "clippy" "rustfmt" ];
        targets = [ "thumbv7em-none-eabihf" ];
      };

  jdk = pkgs.jdk21;

  # Swift is first-class on Darwin. On Linux nixpkgs' swift lags and macro
  # plugins are toolchain-version sensitive, so treat the Linux path as
  # best-effort. See ARCHITECTURE.md section 13.
  swiftAvailable = stdenv.isDarwin || builtins.hasAttr "swift" swiftPkgsSet;

  # Whether `nix flake check` runs the Swift checks.
  #
  # Back on for Linux. It was Darwin-only for four rounds while nixpkgs'
  # packaging was worked out -- NIX_CC, a target-triple mismatch, a missing
  # `ar`, and finally libdispatch not being on the loader path because the
  # corelibs are separate derivations from the `swift` wrapper. None of it was
  # our code, and `nix flake check` should not fail on a dependency's
  # packaging while that is being untangled.
  #
  # It is untangled: the Swift checks pass on Linux. See swiftCorelibs above
  # for the piece that was missing.
  swiftChecked = swiftAvailable;

  # Swift's setup-hook reads NIX_CC and dies with `NIX_CC: unbound variable`
  # without it. The obvious fix -- putting `stdenv.cc` in the inputs -- is
  # WRONG: it puts gcc on the hook's path, swiftc then takes its default target
  # from gcc (`x86_64-pc-linux-gnu`), and Swift's own stdlib is built for
  # `x86_64-unknown-linux-gnu`. The result is
  #
  #   could not find module '_Concurrency' for target 'x86_64-pc-linux-gnu'
  #
  # which reads like a missing module and is really a triple mismatch. NIX_CC
  # is supplied as a plain environment variable instead (see mkCheck), so the
  # hook is satisfied without changing what swiftc thinks it targets.
  # Every part of the Swift toolchain comes from the SAME nixpkgs.
  #
  # I had `binutils` from the pinned 25.05 next to `swift` from unstable, which
  # is a mistake worth naming: two nixpkgs generations disagree about the host
  # triple, and swiftc then reports `glibc not found for x86_64-pc-linux-gnu`
  # while its own modules are built for `x86_64-unknown-linux-gnu`. Every Swift
  # failure so far has carried that warning; it was the cause, not noise.
  # The corelibs, which are separate derivations from the `swift` wrapper.
  #
  # `${swiftPkgsSet.swift}/lib/swift/linux` does not exist: the wrapper and the
  # runtime live in different store paths, which is why a library path built
  # only from `swift` still had no libdispatch.so in it. Named with `or null`
  # so the set can differ between nixpkgs revisions without breaking eval.
  #
  # XCTest is in this list on purpose: if it turns out to be present, the
  # checks can go back to being a real test target.
  swiftCorelibs = lib.optionals (builtins.hasAttr "swiftPackages" swiftPkgsSet) (
    lib.filter (x: x != null) (
      map (n: swiftPkgsSet.swiftPackages.${n} or null) [
        "Dispatch"
        "Foundation"
        "FoundationNetworking"
        "XCTest"
        "swift-corelibs-libdispatch"
      ]
    )
  );

  # Packages whose LIBRARIES are needed but whose `bin` must stay off PATH.
  #
  # `swift-unwrapped` is the compiler without nix's wrapper. Putting it in the
  # inputs shadowed `swift-wrapper/bin/swiftc`, and the unwrapped compiler does
  # not know nix's target triple, so it reported
  #
  #   could not find module 'Swift' for target 'x86_64-pc-linux-gnu';
  #   found: x86_64-unknown-linux-gnu
  #
  # -- the same triple mismatch as round 2, caused the same way: by adding a
  # package to fix a library path and changing which compiler runs. Its `lib`
  # output is still wanted, so it contributes to swiftLibraryPath only.
  swiftLibOnly = lib.optionals (builtins.hasAttr "swiftPackages" swiftPkgsSet) (
    lib.filter (x: x != null) (
      map (n: swiftPkgsSet.swiftPackages.${n} or null) [ "swift-unwrapped" ]
    )
  );

  # Everything needed to COMPILE Swift, minus SwiftPM itself.
  #
  # Split out for one reason: `swiftpmPluginSupport` compiles Swift, so it
  # needs this list, and `swiftPkgs` below CONTAINS its result. Passing the
  # whole of `swiftPkgs` to it would be an infinite recursion, and passing a
  # hand-picked subset is what cost four rounds of missing `NIX_CC`, missing
  # binutils and missing `Foundation`. One list, named, used twice.
  swiftBase = lib.optionals swiftAvailable (
    [ swiftPkgsSet.swift swiftPkgsSet.binutils swiftPkgsSet.stdenv.cc ]
    ++ swiftCorelibs
  );

  swiftBaseLibraryPath = lib.concatStringsSep ":" (
    lib.concatMap (p: [ "${p}/lib" "${p}/lib/swift/linux" ]) (swiftBase ++ swiftLibOnly)
  );

  swiftPkgs = swiftBase
    # The augmented SwiftPM where there is one, so `import
    # CompilerPluginSupport` resolves for every check and shell rather than
    # only for whoever remembered to build the package. `tools/verify
    # swift-macro-support` reports which is in effect.
    ++ lib.optionals (builtins.hasAttr "swiftpm" swiftPkgsSet) [
      (if swiftpmPluginSupport != null then swiftpmPluginSupport else swiftPkgsSet.swiftpm)
    ]
    ++ lib.optionals (builtins.hasAttr "swift-format" swiftPkgsSet) [ swiftPkgsSet.swift-format ];

  # kotlinc, pinned to the SAME version as everything else Kotlin here.
  #
  # This was `pkgs.kotlin`, which is whatever the nixpkgs channel ships. The
  # rest of the repository says 2.1.20 in four places -- both Gradle builds'
  # `kotlin("jvm")`, the KSP pair `2.1.20-1.0.32`, ci.yml's check-no-nix
  # download, and kotlin/README.md's "verified against kotlinc 2.1.20" -- and
  # the flake alone floated. Moving `nixpkgs` from 25.05 to 26.05 for Swift
  # therefore moved the Kotlin compiler as a side effect, which is the exact
  # shape 0c warned about: a change to one language's toolchain landing in
  # another's checks.
  #
  # It matters more for Kotlin than for most compilers because four fixtures
  # assert on kotlinc's own message text (`//~ EXPECT:` in compile_fail/), and
  # that text is the compiler's, not ours -- spec/diagnostics.md says so and
  # says it must not be normalised. A compiler upgrade is allowed to reword
  # it; the fixtures should move when WE move the compiler, on purpose.
  #
  # Owned rather than overridden: `pkgs.kotlin.overrideAttrs` would depend on
  # the shape of nixpkgs' installPhase for a release it was not written for.
  # The distribution is a zip of shell scripts and jars; wrapping it is five
  # lines. Bump `kotlinVersion` and the hash together, and the two Gradle
  # builds and ci.yml with them.
  kotlinVersion = "2.1.20";
  kotlinc = pkgs.stdenvNoCC.mkDerivation {
    pname = "kotlinc";
    version = kotlinVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/JetBrains/kotlin/releases/download/v${kotlinVersion}/kotlin-compiler-${kotlinVersion}.zip";
      hash = "sha256-oRgZew3lX/qyvI1c0DpeOQM8+1M4PWkxvHYd7AeEiRo=";
    };
    nativeBuildInputs = [ pkgs.unzip pkgs.makeWrapper ];
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      rm -f bin/*.bat
      mkdir -p "$out"
      cp -r . "$out/"
      # The scripts find java through JAVA_HOME or PATH. mkCheck sets
      # JAVA_HOME already; --set-default keeps a dev shell with its own
      # JAVA_HOME in charge, and gives a bare `nix shell` a working default.
      for p in "$out"/bin/*; do
        wrapProgram "$p" --set-default JAVA_HOME "${jdk}" --prefix PATH : "${jdk}/bin"
      done
      runHook postInstall
    '';
  };

  rustInputs = [ rustToolchain pkgs.cargo-expand pkgs.cargo-nextest ];
  kotlinInputs = [ jdk pkgs.gradle kotlinc pkgs.ktlint ];
  commonInputs = [ pkgs.git pkgs.jq pkgs.just pkgs.graphviz pkgs.nixpkgs-fmt ];

  # `runCommand` gives no writable HOME, and cargo wants one for its registry
  # cache even with zero dependencies. Every check is --offline --locked so it
  # can never silently reach the network.
  mkCheck = name: inputs: script:
    pkgs.runCommand "tabula-check-${name}"
      {
        nativeBuildInputs = commonInputs ++ inputs;
        # For Swift's setup-hook. A variable, not a package on the path -- see
        # the note on swiftPkgs above.
        NIX_CC = "${pkgs.stdenv.cc}";

        # kotlinc and ktlint are both JVM programs that look for a JDK. The
        # nixpkgs wrappers usually carry one, but "usually" is a guess and nix
        # knows the answer -- the same reason swiftLibraryPath is computed here
        # rather than searched for by the script.
        JAVA_HOME = "${jdk}";
      }
      ''
        export HOME="$TMPDIR/home"
        export CARGO_HOME="$TMPDIR/cargo"
        export GRADLE_USER_HOME="$TMPDIR/gradle"
        export CARGO_NET_OFFLINE=true

        # The sandbox has no network, and the steps that need one must SKIP
        # rather than fail. Stated, not detected: a probe would be the script
        # guessing at something nix already knows for certain, and a wrong
        # guess turns a skip into a red check or, worse, the other way round.
        #
        # `tools/verify` reads this. Unset everywhere else, so the same script
        # in ci.yml's check-no-nix job -- which HAS Maven -- still runs the
        # Gradle and KSP path that only that job can reach.
        export TABULA_OFFLINE=1

        mkdir -p "$HOME" "$CARGO_HOME" "$GRADLE_USER_HOME"

        cp -r ${self} src && chmod -R u+w src && cd src
        ${script}
        touch $out
      '';

  # Where the Swift runtime actually is.
  #
  # `swiftc -print-target-info` reports the *module* search paths, and
  # libdispatch.so is not in them: nixpkgs splits the toolchain across store
  # paths, so the linker finds it via -L flags the wrapper injects while the
  # loader knows nothing about it. Hence
  #
  #   error while loading shared libraries: libdispatch.so
  #
  # nix knows where every one of those packages is, so let nix say it rather
  # than have the script guess. Both `lib` and `lib/swift/linux`, because the
  # toolchain uses both.
  swiftLibraryPath = lib.concatStringsSep ":" (
    lib.concatMap (p: [ "${p}/lib" "${p}/lib/swift/linux" ]) (swiftPkgs ++ swiftLibOnly)
  );

  mkShell = name: extra: env: pkgs.mkShell ({
    inherit name;
    packages = commonInputs ++ extra;
    JAVA_HOME = "${jdk}";
    GRADLE_USER_HOME = "./.gradle-home";
    shellHook = ''
      echo "tabula :: ${name}"
      ${lib.optionalString (!swiftAvailable) ''
        echo "  note: no swift toolchain on ${system}; swift/ is skipped."
      ''}
      ${lib.optionalString (name == "swift" || name == "all") ''
        # The shell opens at the repository root and there is no Package.swift
        # here, so a bare `swift build` fails with "Could not find
        # Package.swift". There are three of them, and which one you want is
        # not guessable -- so say so rather than cd somewhere on someone's
        # behalf.
        echo "  swift packages: swift/ (core)  examples/swift-examples/  swift/macros/ (will not build here)"
        echo "  cd into one before \`swift build\`, or run ./tools/verify swift"
      ''}
    '';
  } // env);

in
{
  inherit
    self system pkgs lib has
    rustToolchain jdk kotlinc kotlinVersion swiftAvailable swiftChecked swiftPkgs
    rustInputs kotlinInputs commonInputs
    swiftLibraryPath gradleRepo swiftDeps swiftpmPluginSupport
    mkCheck mkShell;
}
