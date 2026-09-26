# The Swift toolchain and the check builder, per system. Threaded through the
# other modules in this directory as `ctx`.
#
# The toolchain half is the most expensive code in the repository per line:
# every comment below records a round of `nix flake check` that failed on
# nixpkgs' Swift packaging rather than on anything of ours. It moved here from
# the root nix/context.nix unchanged.
{ self, system, nixpkgs, nixpkgs-swift }:

let
  pkgs = import nixpkgs { inherit system; };

  # Swift comes from its own input. It was added when the pinned nixpkgs
  # (25.05) had Swift 5.8, below the 5.9 macros require; `nixpkgs` is 26.05
  # now and the input is on its way out (see the note in ../flake.nix).
  swiftPkgsSet = import nixpkgs-swift { inherit system; };

  inherit (pkgs) lib stdenv;

  # The whole repository, not just this directory: the checks run
  # `tabular-center-swift/tools/verify` from the root, and read spec/ -- the
  # one thing outside this directory they need; the examples live here. See
  # the same binding in
  # ../../tabular-center-rust/nix/context.nix for why `self.sourceInfo` and
  # why it is checked.
  root =
    let r = self.sourceInfo.outPath; in
    if builtins.pathExists (r + "/spec/conformance")
    then r
    else
      throw ''
        tabular-center-swift: this flake's source is not the whole repository,
        so spec/ is out of reach. Check it from a git checkout
        (`nix flake check ./tabular-center-swift`), or through the root flake,
        with Nix 2.26 or later.
      '';

  has = {
    # `macros/` is the only thing in the repository that links a remote
    # package, and it can build offline exactly when this lock exists.
    swiftLock = builtins.pathExists ./swift-lock.json;
  };

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
    then import ./swift-deps.nix { inherit pkgs lib; lockFile = ./swift-lock.json; }
    else null;


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

  # Exported before any step that runs Swift. The same line was repeated in
  # every Swift check in the root checks.nix.
  swiftSetup = ''export LD_LIBRARY_PATH="${swiftLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"'';

  commonInputs = [ pkgs.git pkgs.jq pkgs.just pkgs.graphviz pkgs.nixpkgs-fmt ];

  mkCheck = name: inputs: script:
    pkgs.runCommand "tabular-center-check-${name}"
      {
        nativeBuildInputs = commonInputs ++ inputs;
        # For Swift's setup-hook. A variable, not a package on the path -- see
        # the note above swiftCorelibs.
        NIX_CC = "${pkgs.stdenv.cc}";
      }
      ''
        export HOME="$TMPDIR/home"

        # The sandbox has no network, and the steps that need one must SKIP
        # rather than fail. Stated, not detected; tools/verify reads it.
        export TABULAR_CENTER_OFFLINE=1

        mkdir -p "$HOME"

        # This directory, spec/, and .editorconfig -- laid out as in the
        # repository, and nothing else. tools/verify runs from the repository
        # root and names paths from there, so the layout is kept; what is left
        # out is the other two languages and the root's own files. A step that
        # reached into either would fail here rather than quietly working,
        # which is what makes "independent" a checked property instead of a
        # claim. spec/ is the one thing all three share by design: it is the
        # cross-language contract.
        mkdir src
        cp -r ${root}/spec src/spec
        cp -r ${root}/tabular-center-swift src/tabular-center-swift
        cp ${root}/.editorconfig src/.editorconfig
        chmod -R u+w src && cd src
        ${script}
        touch $out
      '';

  mkShell = name: extra: pkgs.mkShell {
    inherit name;
    packages = commonInputs ++ extra;
    LD_LIBRARY_PATH = swiftLibraryPath;
    shellHook = ''
      echo "tabular-center :: ${name}"
      ${lib.optionalString (!swiftAvailable) ''
        echo "  note: no swift toolchain on ${system}; tabular-center-swift/ is skipped."
      ''}
      # The shell opens at the repository root and there is no Package.swift
      # there, so a bare `swift build` fails with "Could not find
      # Package.swift". There are three of them, and which one you want is not
      # guessable -- so say so rather than cd somewhere on someone's behalf.
      echo "  swift packages: tabular-center-swift/ (core)  tabular-center-swift/examples/  tabular-center-swift/macros/"
      echo "  cd into one before \`swift build\`, or run ./tools/verify swift"
    '';
  };

in
{
  inherit self system pkgs lib has root swiftAvailable swiftChecked swiftPkgs
    swiftLibraryPath swiftSetup swiftDeps swiftpmPluginSupport commonInputs
    mkCheck mkShell;

  # For the root flake. See `legacyPackages` in ../flake.nix.
  toolchain = {
    inputs = lib.optionals swiftChecked swiftPkgs;
    env = { NIX_CC = "${pkgs.stdenv.cc}"; };
    setup = lib.optionalString swiftChecked swiftSetup;
    available = swiftChecked;
    libraryPath = swiftLibraryPath;
  };
}
