# An offline Maven repository, assembled from `nix/gradle-lock.json`.
#
# The replacement for `gradle-deps.nix`, and a different shape rather than a
# fixed version of the same one. That file was a fixed-output derivation that
# ran Gradle in a sandbox and hashed its cache directory. Both halves were
# wrong:
#
#   - It made the JVM responsible for networking inside a nix build, where a
#     missing route, missing DNS and a CA bundle the JVM will not read are
#     three different problems reported as one sentence: `could not resolve
#     plugin artifact ... Searched in the following repositories`. The build
#     cannot tell them apart and neither can the reader.
#   - A Gradle cache does not hash reproducibly. Locks, `gc.properties` and
#     descriptors keyed by absolute path all move between runs.
#
# Here nothing resolves and nothing is discovered. `tools/gradle-lock` did the
# resolving once, on a machine with network, and committed the answer. Each
# artifact is an ordinary `fetchurl` with a pinned hash, fetched by nix's own
# downloader -- the same mechanism every other dependency in nixpkgs uses, and
# the same one that has never had any of the problems above.
#
# This is the core of gradle2nix, owned rather than depended on. What it leaves
# out is the part that needs a Gradle plugin: resolving configurations the
# example does not build. It does not need that, because the lock is generated
# by building exactly what the check builds.
{ pkgs, lib, lockFile }:

let
  lock = builtins.fromJSON (builtins.readFile lockFile);

  # `path` is already the Maven layout path, so nothing here parses a
  # coordinate. That is deliberate: coordinate-to-path is a rule with
  # exceptions (classifiers, packaging that is not the extension, plugin
  # marker names), and every one of those exceptions would be a second place
  # to get it wrong. The generator resolved the path once and the hash proves
  # it; this file just copies bytes to where the path says.
  files = map
    (a: {
      inherit (a) path;
      src = pkgs.fetchurl {
        inherit (a) url sha256;
      };
    })
    lock.artifacts;

  # One `install -D` per artifact. Not a symlink farm: Gradle writes lock
  # files and `.part` scratch next to what it reads from a repository root,
  # and a tree of symlinks into the store is read-only in a way that surfaces
  # as a permission error three layers down inside the resolution engine.
  copies = lib.concatMapStrings
    (f: ''
      install -Dm444 ${f.src} "$out/${f.path}"
    '')
    files;

in
pkgs.runCommand "tabula-gradle-repo"
{
  # Visible in the build log and in `nix why-depends` output, so a jump in the
  # artifact count shows up as a number rather than as a longer list nobody
  # reads.
  passthru.artifactCount = builtins.length lock.artifacts;
}
  ''
    mkdir -p "$out"
    ${copies}

    # Gradle resolves a `maven { }` repository by path and does not require
    # the checksum sidecars a real server publishes. It will not ask for them
    # and will not warn about their absence; recording them in the lock would
    # double its size to satisfy nothing.
    echo "tabula: ${toString (builtins.length lock.artifacts)} artifacts" > "$out/.tabula-repo"
  ''
