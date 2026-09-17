# `CompilerPluginSupport`, added to nixpkgs' SwiftPM.
#
# Without it `Package.swift` cannot declare a `.macro` target, which is all
# that stands between `swift/macros` and a real macro: no expansion, so
# `pending/Machine.swift` stays out of the build and Swift's diagnostics can be
# checked for their code but never for their source position.
#
# ## Not a SwiftPM package
#
# SwiftPM has a bootstrap problem -- building it needs a working SwiftPM -- so
# packaging it outright is closer to packaging a compiler than a library. And
# nothing here needs a different SwiftPM; it needs one more module in the one
# that is already installed.
#
# ## What is actually missing
#
# nixpkgs' ManifestAPI directory holds exactly three files:
#
#   libPackageDescription.so
#   PackageDescription.swiftdoc
#   PackageDescription.swiftinterface
#
# So `CompilerPluginSupport` is absent outright -- no interface, no library --
# rather than present-but-unexposed. Upstream SwiftPM builds it as a separate
# target beside `PackageDescription` and installs both; this install step keeps
# one of them.
#
# Two things follow. It has to be BUILT, not just declared, so this emits a
# library as well as an interface. And `-enable-library-evolution` is not
# optional: the neighbouring module ships a `.swiftinterface` rather than a
# `.swiftmodule`, which is what that flag produces, and a module built without
# it cannot import one built with it across a version boundary.
#
# ## The link step, and why this is expected to work unpatched
#
# The manifest loader invokes swiftc with `-I <ManifestAPI>` and
# `-L <ManifestAPI>` but links only `-lPackageDescription`, so a second library
# in that directory is findable and not named. Swift's autolinking closes the
# gap: a module records its own library in autolink metadata, and swiftc passes
# it to the linker without being asked. Putting both files in the directory the
# loader already searches should therefore be enough.
#
# If it is not, the symptom is an undefined-symbol error at manifest link time
# rather than `no such module`, and the fix is a patch teaching the loader to
# pass `-lCompilerPluginSupport`. `tools/verify swift-macro-support` reports
# which of the two is happening, which is why it distinguishes them.
# Takes the whole Swift package set, not two packages out of it.
#
# Swift's setup-hook reads `NIX_CC`, and needs Swift's own `binutils` and `cc`
# on the path. `mkCheck` in nix/context.nix already worked all three out -- see
# its note on `NIX_CC` being a variable rather than a package -- and a build
# here naming only `swift` dies on
#
#   setup-hook: line 23: NIX_CC: unbound variable
#
# before compiling anything. Passing the set keeps the two places from drifting
# on which pieces Swift needs.
{ pkgs, lib, swiftPkgsSet, swiftPkgs, swiftLibraryPath }:

let
  inherit (swiftPkgsSet) swiftpm swift;
  version = swiftpm.version or "5.10.1";

  # Pinned to the SwiftPM the toolchain is. A `CompilerPluginSupport` from
  # another release compiles and then disagrees with the `PackageDescription`
  # beside it about types they share, which surfaces as a manifest that builds
  # and produces the wrong targets.
  src = pkgs.fetchFromGitHub {
    owner = "swiftlang";
    repo = "swift-package-manager";
    rev = "swift-${version}-RELEASE";
    # From the first build's mismatch, which is the only way to get one
    # honestly. `swift-5.10.1-RELEASE` is confirmed to exist by that fetch
    # succeeding -- the tag format was a guess until then.
    hash = "sha256-yL/cPCt7pZ0XqbbxEnrbzM2X3EkU9klon7SzO2Z13SA=";
  };

in
pkgs.runCommand "swiftpm-${version}-plugin-support"
{
  # The checks' own input list, not a hand-picked subset.
  #
  # Three rounds were spent rediscovering pieces `swiftPkgs` already had:
  # `NIX_CC`, Swift's binutils and cc, and then `Foundation` --
  #
  #   ContextModel.swift:16:8: error: no such module 'Foundation'
  #
  # which comes from `swiftCorelibs`, a list context.nix builds with a comment
  # explaining that its absence is what used to make people think Swift on
  # Linux was broken. Reusing the list ends that: anything the checks need to
  # compile Swift, this needs too, and by construction rather than by memory.
  nativeBuildInputs = swiftPkgs;

  # A variable, not a package on the path -- the same arrangement every Swift
  # check in nix/checks.nix makes, and for the same reason: the setup-hook
  # reads it rather than looking for a compiler.
  NIX_CC = "${pkgs.stdenv.cc}";

  passthru = { inherit version; inherit (swiftpm) meta; };
} ''
  set -euo pipefail

  # Same as every Swift check. The corelibs are found at compile time through
  # the inputs above and at run time through here.
  export LD_LIBRARY_PATH="${swiftLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

  # A copy, not a symlink farm. The loader passes this directory to swiftc as
  # both -L and -I, and a read-only tree of store symlinks surfaces as a
  # permission error several layers inside the manifest loader.
  mkdir -p "$out"
  cp -r ${swiftpm}/. "$out/"
  chmod -R u+w "$out"

  api="$out/lib/swift/pm/ManifestAPI"
  [ -d "$api" ] || { echo "no ManifestAPI at $api"; exit 1; }

  for m in PackageDescription CompilerPluginSupport; do
    [ -e ${src}/Sources/$m ] || { echo "no Sources/$m in the checkout"; exit 1; }
  done

  # BOTH modules, rebuilt together. Not a preference -- a requirement.
  #
  # `CompilerPluginSupport/TargetExtensions.swift` opens with
  #
  #     @_spi(PackageDescriptionInternal) import PackageDescription
  #
  # and uses that SPI to reach `Target`'s internal initializer and its
  # `.macro` type. nixpkgs installs only a PUBLIC `.swiftinterface` for
  # `PackageDescription`, and a public interface has SPI stripped out of it by
  # definition, so compiling against the installed module fails with
  #
  #     'Target' cannot be constructed because it has no accessible initializers
  #     cannot infer contextual base in reference to member 'macro'
  #
  # There is no flag that recovers erased symbols. The SPI has to be in scope
  # at compile time, which means building the module that declares it, which
  # means building `PackageDescription` here too and installing both.
  #
  # `-emit-private-module-interface-path` is what keeps the SPI visible: the
  # public interface is still emitted for everyone else, and the private one
  # beside it is what `CompilerPluginSupport` reads.
  build="$TMPDIR/build"
  mkdir -p "$build"

  # `-suppress-warnings`, and only here.
  #
  # This compiles SwiftPM's own sources, unmodified, and every warning it
  # produces is about nixpkgs' `Foundation` not being built with library
  # evolution:
  #
  #   warning: module 'Foundation' was not compiled with library evolution
  #   support; using it means binary compatibility for 'PackageDescription'
  #   can't be guaranteed
  #
  # Twice per file, plus an `inconsistently imported as implementation-only`
  # for each. None of it is actionable from here: the source is upstream's and
  # the Foundation is nixpkgs'. Upstream SwiftPM's own build emits the same
  # lines when built this way.
  #
  # Suppressed rather than tolerated because a wall of warnings nobody can act
  # on teaches people to skim build output, which is how a real one gets
  # missed. Errors are unaffected -- `-suppress-warnings` does not touch them,
  # and the four rounds it took to get here were all errors.
  swiftc \
    -suppress-warnings \
    -emit-library -emit-module \
    -enable-library-evolution \
    -emit-module-path "$build/PackageDescription.swiftmodule" \
    -emit-module-interface-path "$build/PackageDescription.swiftinterface" \
    -emit-private-module-interface-path "$build/PackageDescription.private.swiftinterface" \
    -module-name PackageDescription \
    -swift-version 5 \
    -package-description-version 999.0 \
    -o "$build/libPackageDescription.so" \
    ${src}/Sources/PackageDescription/*.swift

  # Same, for the same reason: this module's `@_spi` import of
  # `PackageDescription` warns whenever the latter carries an interface, which
  # it now does by design.
  swiftc \
    -suppress-warnings \
    -emit-library -emit-module \
    -enable-library-evolution \
    -emit-module-path "$build/CompilerPluginSupport.swiftmodule" \
    -emit-module-interface-path "$build/CompilerPluginSupport.swiftinterface" \
    -module-name CompilerPluginSupport \
    -swift-version 5 \
    -package-description-version 999.0 \
    -I "$build" -L "$build" -lPackageDescription \
    -o "$build/libCompilerPluginSupport.so" \
    ${src}/Sources/CompilerPluginSupport/*.swift

  # Replacing nixpkgs' PackageDescription, not sitting beside it. Same source
  # release, so the JSON a manifest serialises is the JSON this SwiftPM
  # deserialises; a mismatch here would surface as a manifest that compiles and
  # then describes the wrong package.
  cp "$build"/libPackageDescription.so "$build"/PackageDescription.swift{module,interface} "$api/"
  cp "$build"/PackageDescription.private.swiftinterface "$api/"
  cp "$build"/libCompilerPluginSupport.so "$build"/CompilerPluginSupport.swift{module,interface} "$api/"

  echo "tabula: CompilerPluginSupport installed into $api"
  ls -1 "$api"
''
