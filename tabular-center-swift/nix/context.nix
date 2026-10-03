# The Swift toolchain and the check builder, per system, threaded through
# this directory as `ctx`. nixpkgs' Swift is assembled here from its separate
# parts -- wrapper, corelibs, runtime library path, NIX_CC -- in the one
# arrangement that compiles and runs on Linux and Darwin; each choice, and the
# failure that forced it, is ARCHITECTURE.md 16, "Nix: Swift". A check sees
# this directory, spec/ and .editorconfig.
{ self, system, nixpkgs, nixpkgs-swift }:

let
  pkgs = import nixpkgs { inherit system; };

  swiftPkgsSet = import nixpkgs-swift { inherit system; };

  inherit (pkgs) lib stdenv;

  wholeCheckout = builtins.pathExists (self.sourceInfo.outPath + "/spec/conformance");
  fromCheckout = path:
    if wholeCheckout
    then path
    else
      throw ''
        tabular-center-swift: this flake's source is not the whole repository,
        so spec/ is out of reach. Check it from a git checkout
        (`nix flake check ./tabular-center-swift`), or through the root flake,
        with Nix 2.26 or later.
      '';

  specSrc = builtins.path { path = fromCheckout ../../spec; name = "tabular-center-spec"; };
  editorconfig = builtins.path { path = fromCheckout ../../.editorconfig; name = "tabular-center-editorconfig"; };
  langSrc = builtins.path { path = ./..; name = "tabular-center-swift-src"; };

  has = {
    swiftLock = builtins.pathExists ./swift-lock.json;
  };

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


  swiftAvailable = stdenv.isDarwin || builtins.hasAttr "swift" swiftPkgsSet;

  swiftChecked = swiftAvailable;

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

  swiftLibOnly = lib.optionals (builtins.hasAttr "swiftPackages" swiftPkgsSet) (
    lib.filter (x: x != null) (
      map (n: swiftPkgsSet.swiftPackages.${n} or null) [ "swift-unwrapped" ]
    )
  );

  swiftBase = lib.optionals swiftAvailable (
    [ swiftPkgsSet.swift swiftPkgsSet.binutils swiftPkgsSet.stdenv.cc ]
    ++ swiftCorelibs
  );

  swiftBaseLibraryPath = lib.concatStringsSep ":" (
    lib.concatMap (p: [ "${p}/lib" "${p}/lib/swift/linux" ]) (swiftBase ++ swiftLibOnly)
  );

  swiftPkgs = swiftBase
    ++ lib.optionals (builtins.hasAttr "swiftpm" swiftPkgsSet) [
      (if swiftpmPluginSupport != null then swiftpmPluginSupport else swiftPkgsSet.swiftpm)
    ]
    ++ lib.optionals (builtins.hasAttr "swift-format" swiftPkgsSet) [ swiftPkgsSet.swift-format ];


  swiftLibraryPath = lib.concatStringsSep ":" (
    lib.concatMap (p: [ "${p}/lib" "${p}/lib/swift/linux" ]) (swiftPkgs ++ swiftLibOnly)
  );

  swiftSetup = ''
    export NIX_CC="${pkgs.stdenv.cc}"
    export LD_LIBRARY_PATH="${swiftLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';

  commonInputs = [ pkgs.git pkgs.jq pkgs.just pkgs.graphviz pkgs.nixpkgs-fmt ];

  mkCheck = name: inputs: script:
    pkgs.runCommand "tabular-center-check-${name}"
      {
        nativeBuildInputs = commonInputs ++ inputs;
        NIX_CC = "${pkgs.stdenv.cc}";
      }
      ''
        export HOME="$TMPDIR/home"

        export TABULAR_CENTER_OFFLINE=1

        mkdir -p "$HOME"

        mkdir src
        cp -r ${specSrc} src/spec
        cp -r ${langSrc} src/tabular-center-swift
        cp ${editorconfig} src/.editorconfig
        chmod -R u+w src && cd src

        patchShebangs --build . >/dev/null
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
      echo "  swift packages: tabular-center-swift/ (core)  tabular-center-swift/examples/  tabular-center-swift/macros/"
      echo "  cd into one before \`swift build\`, or run ./tools/verify swift"
    '';
  };

in
{
  inherit self system pkgs lib has specSrc langSrc editorconfig swiftAvailable swiftChecked swiftPkgs
    swiftLibraryPath swiftSetup swiftDeps swiftpmPluginSupport commonInputs
    mkCheck mkShell;

  toolchain = {
    inputs = lib.optionals swiftChecked swiftPkgs;
    env = { NIX_CC = "${pkgs.stdenv.cc}"; };
    setup = lib.optionalString swiftChecked swiftSetup;
    available = swiftChecked;
    libraryPath = swiftLibraryPath;
  };
}
