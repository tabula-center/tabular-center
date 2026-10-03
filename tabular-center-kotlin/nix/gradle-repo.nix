# An offline Maven repository, assembled from nix/gradle-lock.json: one
# fetchurl per artifact, installed at the Maven layout path the lock records.
# Nothing resolves here; tools/gradle-lock resolved once, with network, and
# committed the answer. ARCHITECTURE.md 16, "Nix: Kotlin".
{ pkgs, lib, lockFile }:

let
  lock = builtins.fromJSON (builtins.readFile lockFile);

  files = map
    (a: {
      inherit (a) path;
      src = pkgs.fetchurl {
        inherit (a) url sha256;
      };
    })
    lock.artifacts;

  copies = lib.concatMapStrings
    (f: ''
      install -Dm444 ${f.src} "$out/${f.path}"
    '')
    files;

in
pkgs.runCommand "tabular-center-gradle-repo"
{
  passthru.artifactCount = builtins.length lock.artifacts;
}
  ''
    mkdir -p "$out"
    ${copies}

    echo "tabular-center: ${toString (builtins.length lock.artifacts)} artifacts" > "$out/.tabular-center-repo"
  ''
