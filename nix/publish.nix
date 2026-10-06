# Publication, as two apps.
#
#   nix run .#release -- X.Y.Z     bump every manifest from VERSION, run
#                                  `nix flake check`, commit and tag
#   nix run .#publish              dry run of every registry
#   nix run .#publish -- --execute [--only rust|kotlin|swift]
#
# `release` is safe and the default; `publish` is destructive (a version is
# burned forever on crates.io) and opt-in. RELEASING.md is the procedure;
# ARCHITECTURE.md 16 says why each step is shaped as it is.
ctx:

let
  inherit (ctx) pkgs lib has toolchains commonInputs;
  rustInputs = toolchains.rust.inputs;
  kotlinInputs = toolchains.kotlin.inputs;
  swiftInputs = toolchains.swift.inputs;
in
{
  release = pkgs.writeShellApplication {
    name = "tabular-center-release";
    runtimeInputs = commonInputs ++ rustInputs ++ [ pkgs.gnused ];
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

      if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
        echo "tag v$version already exists; delete it first (git tag -d v$version)"
        echo "if it was never pushed, or choose another version"
        exit 1
      fi

      restore() {
        echo "restoring the tree"
        git checkout -- .
      }
      trap 'restore' ERR

      echo "== setting version to $version =="
      echo "$version" > VERSION
      ./tools/compat add "$version"

      sed -i "s/^version = \".*\"$/version = \"$version\"/" tabular-center-rust/Cargo.toml

      echo "== refreshing lockfiles =="
      (cd tabular-center-rust && cargo update --workspace --offline)
      (cd tabular-center-rust/examples && cargo update --workspace --offline)
      sed -i "/^name = \"tabular-center\"$/{n;s/^version = \".*\"$/version = \"$version\"/}" \
        tabular-center-rust/examples/05-iced/Cargo.lock

      echo "== verifying: nix flake check =="
      nix flake check --print-build-logs

      echo "== committing and tagging =="
      trap - ERR
      git add -A
      if git diff --cached --quiet; then
        echo "the tree already carries $version: nothing to commit, tagging HEAD"
      else
        git commit -m "release: $version"
      fi
      git tag -a "v$version" -m "tabular-center $version"

      echo
      echo "tagged v$version. Nothing has been pushed or published."
      echo "  git push --follow-tags"
      echo "  nix run .#publish -- --execute"
    '';
  };

  publish = pkgs.writeShellApplication {
    name = "tabular-center-publish";
    runtimeInputs = commonInputs ++ rustInputs ++ kotlinInputs ++ swiftInputs ++ [ pkgs.curl pkgs.zip ];
    text = ''
      execute=0
      only=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --execute) execute=1 ;;
          --only)
            only="''${2:-}"
            case "$only" in
              rust|kotlin|swift) ;;
              *) echo "publish: --only takes rust, kotlin or swift, not '$only'"; exit 2 ;;
            esac
            shift ;;
          *) echo "publish: unknown argument '$1'"; exit 2 ;;
        esac
        shift
      done
      want() { [ -z "$only" ] || [ "$only" = "$1" ]; }

      version="$(cat VERSION 2>/dev/null || echo unknown)"
      if [ "$execute" -eq 0 ]; then
        echo "DRY RUN for $version. Pass --execute to publish for real."
        echo
      fi

      if want rust; then
      echo "== rust: crates.io =="
      if [ "$execute" -eq 1 ]; then
        (cd tabular-center-rust && cargo publish -p tabular-center)
      else
        (cd tabular-center-rust && cargo publish -p tabular-center --dry-run)
      fi
      fi

      if want kotlin; then
      echo "== kotlin: maven central =="
      bundle_dir="$(mktemp -d)"
      if [ "$execute" -eq 1 ]; then
        for v in MAVEN_CENTRAL_USERNAME MAVEN_CENTRAL_PASSWORD SIGNING_KEY SIGNING_KEY_ID; do
          if [ -z "''${!v:-}" ]; then
            echo "publish: $v is not set (the maven-central environment holds it in CI)"
            exit 1
          fi
        done
      fi
      tabular-center-kotlin/tools/central-bundle "$bundle_dir/staging" "$bundle_dir/bundle.zip"
      if [ "$execute" -eq 1 ]; then
        auth="$(printf '%s:%s' "$MAVEN_CENTRAL_USERNAME" "$MAVEN_CENTRAL_PASSWORD" | base64 | tr -d '\n')"
        api="https://central.sonatype.com/api/v1/publisher"
        id="$(curl -sS --fail-with-body -X POST -H "Authorization: Bearer $auth" \
          -F "bundle=@$bundle_dir/bundle.zip" \
          "$api/upload?name=tabular-center-$version&publishingType=AUTOMATIC")"
        echo "  uploaded: deployment $id"
        state=""
        for _ in $(seq 1 60); do
          status="$(curl -sS --fail-with-body -X POST -H "Authorization: Bearer $auth" "$api/status?id=$id")"
          state="$(printf '%s' "$status" | jq -r .deploymentState)"
          case "$state" in
            PUBLISHED|PUBLISHING) echo "  central: $state"; break ;;
            FAILED) echo "  central refused the bundle:"; printf '%s' "$status" | jq .; exit 1 ;;
            *) sleep 20 ;;
          esac
        done
        case "$state" in
          PUBLISHED|PUBLISHING) ;;
          *) echo "  central: still $state after 20 minutes; see deployment $id in the portal"; exit 1 ;;
        esac
      else
        echo "  would upload $bundle_dir/bundle.zip to the Central Portal (needs --execute)"
      fi
      rm -rf "$bundle_dir"

      fi

      if want swift; then
      echo "== swift: mirror, then package index =="
      if [ "$execute" -eq 1 ]; then
        git push --follow-tags
        echo "  pushed v$version; swift-mirror publishes tabular-center-swift $version"
      else
        echo "  would: git push --follow-tags   (tag v$version)"
        echo "  which triggers swift-mirror: tabula-center/tabular-center-swift @ $version"
      fi
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
