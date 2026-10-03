# nixpkgs' SwiftPM, rebuilt with `CompilerPluginSupport` in its ManifestAPI,
# so a Package.swift can declare a `.macro` target.
#
#   nix build ./tabular-center-swift#swiftpm-plugin-support
#   ls result/lib/swift/pm/ManifestAPI
#
# An overrideAttrs, because the manifest API path is baked into the binary.
# PackageDescription is rebuilt with a private interface for the SPI
# CompilerPluginSupport imports, and both modules link into the one library
# the manifest loader names. The build fails unless the module and its symbols
# are there. ARCHITECTURE.md 16, "Nix: Swift".
{ pkgs, lib, swiftPkgsSet }:

let
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

  postFixup = (old.postFixup or "") + ''
    api="$out/lib/swift/pm/ManifestAPI"
    [ -d "$api" ] || { echo "no ManifestAPI at $api"; exit 1; }

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

    swiftc -suppress-warnings -c -whole-module-optimization \
      -enable-library-evolution -swift-version 5 \
      -package-description-version 999.0 \
      -module-name PackageDescription \
      -emit-module-path "$api/PackageDescription.swiftmodule" \
      -emit-module-interface-path "$api/PackageDescription.swiftinterface" \
      -emit-private-module-interface-path "$api/PackageDescription.private.swiftinterface" \
      -o "$TMPDIR/PackageDescription.o" \
      "$src"/Sources/PackageDescription/*.swift

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

    [ -e "$api/CompilerPluginSupport.swiftmodule" ] || {
      echo "tabular-center: CompilerPluginSupport.swiftmodule is missing after postFixup"
      exit 1
    }
    ${nmExported} "$api/libPackageDescription.so" > "$TMPDIR/lib.syms"
    if ! grep -q CompilerPluginSupport "$TMPDIR/lib.syms"; then
      echo "tabular-center: libPackageDescription.so defines no CompilerPluginSupport"
      echo "  symbols; the module is findable and will not link."
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
