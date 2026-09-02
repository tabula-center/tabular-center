# Publication, as two apps.
#
# `release` prepares: it is the only thing that writes a version number, and it
# refuses to tag a tree that does not pass `tools/verify`. `publish` ships, and
# is a dry run unless told otherwise.
#
# The split matters because the failure modes differ. A bad release is a
# corrected commit; a bad publish is a version number burned forever on
# crates.io, which does not allow deletion. So the destructive step is opt-in
# and the safe one is the default.
ctx:

let
  inherit (ctx) pkgs lib has rustInputs kotlinInputs swiftPkgs swiftAvailable commonInputs;
in
{
  release = pkgs.writeShellApplication {
    name = "tabula-release";
    runtimeInputs = commonInputs ++ rustInputs ++ lib.optionals has.kotlin kotlinInputs;
    text = ''
      version="''${1:-}"
      if [ -z "$version" ]; then
        echo "usage: nix run .#release -- <version>"
        echo "current: $(cat VERSION 2>/dev/null || echo none)"
        exit 2
      fi

      if [ -n "$(git status --porcelain)" ]; then
        echo "working tree is dirty; commit or stash first"
        exit 1
      fi

      echo "== setting version to $version =="
      echo "$version" > VERSION

      # VERSION is the single source of truth; every manifest is derived from
      # it. Three files drifting apart is the normal way a polyglot release
      # goes wrong.
      sed -i "s/^version = \".*\"$/version = \"$version\"/" rust/Cargo.toml
      if [ -f kotlin/build.gradle.kts ]; then
        sed -i "s/^version = \".*\"$/version = \"$version\"/" kotlin/build.gradle.kts
      fi

      echo "== verifying =="
      ./tools/verify

      echo "== committing and tagging =="
      git add -A
      git commit -m "release: $version"
      git tag -a "v$version" -m "tabula $version"

      echo
      echo "tagged v$version. Nothing has been pushed or published."
      echo "  git push --follow-tags"
      echo "  nix run .#publish -- --execute"
    '';
  };

  publish = pkgs.writeShellApplication {
    name = "tabula-publish";
    runtimeInputs = commonInputs ++ rustInputs
      ++ lib.optionals has.kotlin kotlinInputs
      ++ lib.optionals (has.swift && swiftAvailable) swiftPkgs;
    text = ''
      execute=0
      for a in "$@"; do [ "$a" = "--execute" ] && execute=1; done

      version="$(cat VERSION 2>/dev/null || echo unknown)"
      if [ "$execute" -eq 0 ]; then
        echo "DRY RUN for $version. Pass --execute to publish for real."
        echo
      fi

      echo "== rust: crates.io =="
      if [ "$execute" -eq 1 ]; then
        # Needs CARGO_REGISTRY_TOKEN. Only the library is published; the
        # conformance harness and the examples are publish = false.
        (cd rust && cargo publish -p tabula)
      else
        (cd rust && cargo publish -p tabula --dry-run)
      fi

      ${lib.optionalString has.kotlinGradle ''
        echo "== kotlin: maven =="
        if [ "$execute" -eq 1 ]; then
          (cd kotlin && gradle --no-daemon publish)
        else
          (cd kotlin && gradle --no-daemon publishToMavenLocal)
        fi
      ''}
      ${lib.optionalString (!has.kotlinGradle) ''
        echo "== kotlin: skipped =="
        echo "  no Gradle build yet; the module compiles with kotlinc alone."
      ''}

      echo "== swift: package index =="
      # Swift Package Index resolves from git tags rather than a registry, so
      # publishing is pushing the tag `release` created. Nothing to upload.
      if [ "$execute" -eq 1 ]; then
        git push --follow-tags
      else
        echo "  would: git push --follow-tags   (tag v$version)"
      fi

      echo
      if [ "$execute" -eq 1 ]; then
        echo "published $version"
      else
        echo "dry run complete; nothing was published"
      fi
    '';
  };
}
