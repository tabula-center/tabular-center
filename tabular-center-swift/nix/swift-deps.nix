# SwiftPM's dependency checkouts, assembled from nix/swift-lock.json, so
# `swift build --disable-automatic-resolution` runs offline. SwiftPM needs
# two things to believe it has resolved: `.build/checkouts/<name>/`, the
# unpacked source, and `.build/workspace-state.json` saying which revision it
# is. tools/swift-lock resolved once, with network, and committed the answer.
# ARCHITECTURE.md 16, "Nix: Swift".
{ pkgs, lib, lockFile }:

let
  lock = builtins.fromJSON (builtins.readFile lockFile);

  checkouts = map
    (d: {
      name = lib.removeSuffix ".git" (baseNameOf d.location);
      inherit (d) identity location revision version;
      src = pkgs.fetchurl { inherit (d) url sha256; };
    })
    lock.dependencies;

  copies = lib.concatMapStrings
    (c: ''
      mkdir -p "$out/checkouts/${c.name}"
      tar -xzf ${c.src} -C "$out/checkouts/${c.name}" --strip-components=1
      chmod -R u+w "$out/checkouts/${c.name}"
    '')
    checkouts;

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
pkgs.runCommand "tabular-center-swift-deps"
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
