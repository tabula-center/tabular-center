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
  has = {
    kotlin = builtins.pathExists ../kotlin/src;
    kotlinGradle = builtins.pathExists ../kotlin/settings.gradle.kts;
    swift = builtins.pathExists ../swift/Package.swift;
    rustConformance = builtins.pathExists ../rust/tabula-conformance/Cargo.toml;
    examples = builtins.pathExists ../examples/rust/Cargo.toml;
  };

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

  swiftPkgs = lib.optionals swiftAvailable (
    [ swiftPkgsSet.swift swiftPkgsSet.binutils swiftPkgsSet.stdenv.cc ]
    ++ swiftCorelibs
    ++ lib.optionals (builtins.hasAttr "swiftpm" swiftPkgsSet) [ swiftPkgsSet.swiftpm ]
    ++ lib.optionals (builtins.hasAttr "swift-format" swiftPkgsSet) [ swiftPkgsSet.swift-format ]
  );

  rustInputs = [ rustToolchain pkgs.cargo-expand pkgs.cargo-nextest ];
  kotlinInputs = [ jdk pkgs.gradle pkgs.kotlin pkgs.ktlint ];
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
      }
      ''
        export HOME="$TMPDIR/home"
        export CARGO_HOME="$TMPDIR/cargo"
        export GRADLE_USER_HOME="$TMPDIR/gradle"
        export CARGO_NET_OFFLINE=true
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
    rustToolchain jdk swiftAvailable swiftChecked swiftPkgs
    rustInputs kotlinInputs commonInputs
    swiftLibraryPath
    mkCheck mkShell;
}
