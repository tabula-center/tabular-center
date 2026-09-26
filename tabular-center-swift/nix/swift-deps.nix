# SwiftPM's dependency checkouts, assembled from `nix/swift-lock.json`.
#
# The Swift half of the same idea as `gradle-repo.nix`: nothing resolves inside
# a nix build. `tools/swift-lock` did the resolving once, on a machine with
# network, and committed the answer. Each dependency is a `fetchurl` with a
# pinned hash, fetched by nix's own downloader.
#
# ## What SwiftPM needs to believe it has already resolved
#
# Two things, and only two:
#
#   .build/checkouts/<name>/      the unpacked source
#   .build/workspace-state.json   a record saying which revision that is
#
# Given both, `swift build --disable-automatic-resolution` never contacts a
# remote. Without the state file it re-resolves and fails offline, which is the
# failure mode worth naming because it looks like the checkouts were ignored.
#
# This is the core of swiftpm2nix, owned rather than depended on, for the same
# reason `gradle-repo.nix` is the core of gradle2nix: the part we need is
# small, and the part we do not need is most of it.
{ pkgs, lib, lockFile }:

let
  lock = builtins.fromJSON (builtins.readFile lockFile);

  # `fetchurl`, not `fetchzip`, and the difference is the whole of a bug worth
  # recording.
  #
  # `fetchzip` unpacks before hashing, so its hash is the NAR hash of the
  # extracted tree. `tools/swift-lock` records `sha256sum` of the tarball
  # bytes, because that is what a generator with no nix on the machine can
  # compute. The two disagree by construction and the build says so:
  #
  #     specified: sha256-h6j1OCxXm+d3L+zSF5kNsr5tqlYBZNxx2Z4pyXCbcLk=
  #     got:       sha256-QhHWBLnwBqvuSPVWCh+HkFVaYLuWdwCL2oqTf20HtDQ=
  #
  # Which reads like a wrong hash and is not: both are correct hashes of
  # different things. Taking the `got:` value would have "fixed" it by pinning
  # a NAR hash into a file whose other field is a tarball hash, and the next
  # `swift-lock --check` would have called the lock stale forever.
  #
  # So `fetchurl` hashes the bytes that were downloaded, matching the
  # generator, and the unpacking moves below where it is ordinary `tar`. Same
  # arrangement as `gradle-repo.nix`, which fetches artifacts whole for the
  # same reason.
  checkouts = map
    (d: {
      # SwiftPM names the checkout directory after the repository, not the
      # identity. A mismatch makes SwiftPM re-resolve rather than complain, so
      # it is taken from the URL.
      name = lib.removeSuffix ".git" (baseNameOf d.location);
      inherit (d) identity location revision version;
      src = pkgs.fetchurl { inherit (d) url sha256; };
    })
    lock.dependencies;

  # `--strip-components=1` because GitHub's `/archive/<rev>.tar.gz` wraps
  # everything in `<repo>-<rev>/`, and SwiftPM expects the package root
  # directly under the checkout directory.
  copies = lib.concatMapStrings
    (c: ''
      mkdir -p "$out/checkouts/${c.name}"
      tar -xzf ${c.src} -C "$out/checkouts/${c.name}" --strip-components=1
      chmod -R u+w "$out/checkouts/${c.name}"
    '')
    checkouts;

  # Version 6 is what SwiftPM 5.9-5.10 writes. Pinned rather than probed: a
  # state file in a version the toolchain does not recognise is discarded
  # silently and resolution starts again, so this has to move deliberately when
  # the toolchain does.
  workspaceState = builtins.toJSON {
    version = 6;
    object = {
      artifacts = [ ];
      dependencies = map
        (c: {
          basedOn = null;
          packageRef = {
            inherit (c) identity location;
            name = c.name;
            kind = "remoteSourceControl";
          };
          state = {
            name = "sourceControlCheckout";
            checkoutState = {
              inherit (c) revision;
            } // lib.optionalAttrs (c.version != "") { inherit (c) version; };
          };
          subpath = c.name;
        })
        checkouts;
    };
  };

in
pkgs.runCommand "tabula-swift-deps"
{
  passthru.dependencyCount = builtins.length lock.dependencies;
}
  ''
    mkdir -p "$out/checkouts"
    ${copies}
    cat > "$out/workspace-state.json" <<'STATE'
    ${workspaceState}
    STATE
  ''
