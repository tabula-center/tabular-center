# nixpkgs' SwiftPM, rebuilt with `CompilerPluginSupport` in its ManifestAPI.
#
# An `overrideAttrs`, not a copy. Four rounds were spent on a copy before the
# reason it cannot work became clear, and it is worth stating plainly:
#
#   $ swift-package dump-package
#   ... -I /nix/store/k6b07...-swiftpm-5.10.1/lib/swift/pm/ManifestAPI ...
#
# `swift-package` emits that path while running from a different store path
# entirely. The manifest API location is BAKED INTO THE BINARY at its own build
# time -- not derived from where the binary sits, and not read from the `swift`
# wrapper, which contains no reference to swiftpm at all. So a copy beside the
# original inherits the original's baked path and is never consulted, however
# early it appears on PATH and whether or not its symlinks are dereferenced.
#
# The module has to be inside the derivation that produces that path. Which
# also makes this simpler than the copy was: swiftpm builds from source, so
# `Sources/CompilerPluginSupport` is already in the build tree and no separate
# fetch is needed.
#
# ## Why PackageDescription is rebuilt too
#
# `CompilerPluginSupport/TargetExtensions.swift` opens with
#
#     @_spi(PackageDescriptionInternal) import PackageDescription
#
# and uses that SPI to reach `Target`'s internal initializer and its `.macro`
# type. A public `.swiftinterface` has SPI stripped by definition, so compiling
# against the installed module fails with
#
#     'Target' cannot be constructed because it has no accessible initializers
#
# No flag recovers erased symbols. `-emit-private-module-interface-path` keeps
# them: the public interface is still emitted for everyone else, and the private
# one beside it is what `CompilerPluginSupport` reads.
{ pkgs, lib, swiftPkgsSet }:

let
  # "Exported, defined symbols of this library", per object format.
  #
  # `nm -D` reads an ELF dynamic symbol table. Darwin libraries are Mach-O --
  # whatever the file is called; nixpkgs keeps the `.so` name -- and have no
  # such table, so on macOS `nm -D` stopped the build with "File format has no
  # dynamic symbol table" after a twelve-minute compile that had SUCCEEDED.
  # `-gU` (external, defined) is the Mach-O spelling, and both cctools' and
  # LLVM's nm accept it. Swift's Mach-O symbols carry a leading underscore
  # (`_$s21CompilerPluginSupport...`), which the substring match below does
  # not care about.
  nmExported =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "nm -gU"
    else "nm -D --defined-only";
  nmDefined =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "nm -U"
    else "nm --defined-only";
in
swiftPkgsSet.swiftpm.overrideAttrs (old: {
  pname = "${old.pname or "swiftpm"}-plugin-support";

  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.patchelf ];

  # `postFixup`, not `postInstall`.
  #
  # The override landed -- the manifest loader named
  # `swiftpm-plugin-support-5.10.1` -- and the module was still absent, with
  # the build reporting success. A derivation with a custom `installPhase`
  # that omits `runHook postInstall` skips the hook silently, which is what
  # happened: the addition was attached to a phase nothing called.
  #
  # `fixupPhase` is stdenv's own and always runs `postFixup`. The assertion at
  # the end makes the difference moot either way: a phase that does not run
  # now fails the build instead of producing a quiet copy of the original.
  postFixup = (old.postFixup or "") + ''
    api="$out/lib/swift/pm/ManifestAPI"
    [ -d "$api" ] || { echo "no ManifestAPI at $api"; exit 1; }

    # Found, not guessed.
    #
    # `$NIX_BUILD_TOP/source` was the guess and it was wrong; stdenv names the
    # unpacked directory after the tarball, which is a fact about nixpkgs'
    # `srcs` that this file should not need to know. `$sourceRoot` is stdenv's
    # own answer and is still in scope during `fixupPhase`, and the search is
    # there for the case where it is not -- looking for the module by name is
    # the one question with an unambiguous answer.
    src=""
    for candidate in "''${SWIFTPM_SOURCE:-}" "''${sourceRoot:-}" "$NIX_BUILD_TOP/source"; do
      [ -n "$candidate" ] && [ -d "$candidate/Sources/CompilerPluginSupport" ] && {
        src="$candidate"; break
      }
    done
    if [ -z "$src" ]; then
      found="$(find "$NIX_BUILD_TOP" -maxdepth 4 -type d -name CompilerPluginSupport         -path '*/Sources/*' 2>/dev/null | head -1)"
      [ -n "$found" ] && src="$(dirname "$(dirname "$found")")"
    fi
    if [ -z "$src" ]; then
      echo "tabular-center: could not find Sources/CompilerPluginSupport under $NIX_BUILD_TOP"
      echo "  This override compiles two modules out of swiftpm's own checkout."
      echo "  Contents of the build directory:"
      ls -1 "$NIX_BUILD_TOP" | head -20
      exit 1
    fi
    echo "tabular-center: swiftpm sources at $src"

    # ONE library, two modules.
    #
    # The loader links `-lPackageDescription` and nothing else. Shipping
    # `libCompilerPluginSupport.so` beside it did not work, and neither did
    # recording it as a DT_NEEDED dependency: modern `ld` defaults to
    # `--no-copy-dt-needed-entries` and refuses to resolve symbols from
    # libraries it was not given directly. The result both times was
    #
    #   undefined reference to '...Target...CompilerPluginSupportE5macro...'
    #
    # So the objects go into the library the loader actually names. Each module
    # is compiled to an object separately -- they are still two modules, with
    # two interfaces, and `import CompilerPluginSupport` is still its own
    # import -- and both objects are linked into `libPackageDescription.so`.
    # That is a packaging decision, not a language one: a Swift module's code
    # does not have to live in a library of the same name.
    #
    # -suppress-warnings: this compiles upstream's sources unmodified, and
    # every warning is nixpkgs' Foundation not being built with library
    # evolution. None of it is actionable here, and a wall of unactionable
    # warnings teaches people to skim build output. Errors are unaffected.
    #
    # -package-description-version: `PackageDescription` gates its own API with
    # `@available(_PackageDescription 5.7)`, resolved from this flag. Without
    # it every gated symbol is unavailable to its own module.
    swiftc -suppress-warnings -c -whole-module-optimization \
      -enable-library-evolution -swift-version 5 \
      -package-description-version 999.0 \
      -module-name PackageDescription \
      -emit-module-path "$api/PackageDescription.swiftmodule" \
      -emit-module-interface-path "$api/PackageDescription.swiftinterface" \
      -emit-private-module-interface-path "$api/PackageDescription.private.swiftinterface" \
      -o "$TMPDIR/PackageDescription.o" \
      "$src"/Sources/PackageDescription/*.swift

    # `@_spi(PackageDescriptionInternal) import PackageDescription` reaches
    # `Target`'s internal initializer and its `.macro` type. A public
    # `.swiftinterface` has SPI stripped by definition, which is why the
    # private one above exists and why `-I "$api"` finds it here.
    swiftc -suppress-warnings -c -whole-module-optimization \
      -enable-library-evolution -swift-version 5 \
      -package-description-version 999.0 \
      -module-name CompilerPluginSupport -I "$api" \
      -emit-module-path "$api/CompilerPluginSupport.swiftmodule" \
      -emit-module-interface-path "$api/CompilerPluginSupport.swiftinterface" \
      -o "$TMPDIR/CompilerPluginSupport.o" \
      "$src"/Sources/CompilerPluginSupport/*.swift

    swiftc -emit-library -o "$api/libPackageDescription.so" \
      "$TMPDIR/PackageDescription.o" "$TMPDIR/CompilerPluginSupport.o"

    # The build must not succeed without the module.
    #
    # Four rounds were spent on an augmented SwiftPM that was correct and
    # unreachable, and a fifth on one whose build hook never ran. Every one of
    # them reported success. This is the assertion that makes "it built" and
    # "it worked" the same statement.
    [ -e "$api/CompilerPluginSupport.swiftmodule" ] || {
      echo "tabular-center: CompilerPluginSupport.swiftmodule is missing after postFixup"
      exit 1
    }
    # And the symbols, not just the module. Two earlier attempts produced a
    # findable module whose code the linker could not reach, and both reported
    # success here.
    #
    # Through a file, never `nm ... | grep -q`. stdenv runs this with
    # `set -o pipefail`, and `grep -q` exits at its first match: `nm`, still
    # writing a symbol table far larger than a pipe buffer, dies of SIGPIPE,
    # and pipefail turns a FOUND symbol into a failed pipeline. That reported
    # "defines no CompilerPluginSupport symbols" for a library that did --
    # an assertion lying in the opposite direction from the five rounds above,
    # and just as hard to see, because whether it lies depends on where in
    # nm's output the first match falls.
    ${nmExported} "$api/libPackageDescription.so" > "$TMPDIR/lib.syms"
    if ! grep -q CompilerPluginSupport "$TMPDIR/lib.syms"; then
      echo "tabular-center: libPackageDescription.so defines no CompilerPluginSupport"
      echo "  symbols; the module is findable and will not link."
      # Which half lost them: the object (compile) or the library (link).
      ${nmDefined} "$TMPDIR/CompilerPluginSupport.o" > "$TMPDIR/obj.syms" || true
      echo "  CompilerPluginSupport.o: $(grep -c CompilerPluginSupport "$TMPDIR/obj.syms" || true) matching symbol(s)"
      echo "  libPackageDescription.so: $(wc -l < "$TMPDIR/lib.syms") exported symbol(s) in all"
      exit 1
    fi
    echo "tabular-center: $(grep -c CompilerPluginSupport "$TMPDIR/lib.syms") CompilerPluginSupport symbol(s) exported"

    echo "tabular-center: ManifestAPI now holds"
    ls -1 "$api"
  '';
})
