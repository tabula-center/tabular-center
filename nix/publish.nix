# Publication, as two apps.
#
# `release` prepares: it is the only thing that writes a version number, and it
# refuses to tag a tree that does not pass `nix flake check`. `publish` ships, and
# is a dry run unless told otherwise.
#
# The split matters because the failure modes differ. A bad release is a
# corrected commit; a bad publish is a version number burned forever on
# crates.io, which does not allow deletion. So the destructive step is opt-in
# and the safe one is the default.
ctx:

let
  inherit (ctx) pkgs lib has toolchains commonInputs;
  rustInputs = toolchains.rust.inputs;
  kotlinInputs = toolchains.kotlin.inputs;
  # Empty where there is no Swift toolchain, so it can be appended as is.
  swiftInputs = toolchains.swift.inputs;
in
{
  release = pkgs.writeShellApplication {
    name = "tabular-center-release";
    # cargo, to refresh lockfiles, and GNU sed for the in-place edits below on
    # any host. The checks themselves run in nix's sandbox (`nix flake check`),
    # so they need nothing from here -- and `nix` itself is the host's, kept on
    # PATH by writeShellApplication.
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

      # A failed release must leave nothing behind. Everything below edits
      # tracked files, and `tools/verify` runs `--locked`, so a half-applied
      # bump would fail every later run with a stale-lockfile error that says
      # nothing about the real cause.
      # `git checkout -- .` only, never `git clean`: everything this script
      # touches is tracked, and deleting a developer's untracked files to undo
      # a version bump would be a wildly disproportionate response.
      restore() {
        echo "restoring the tree"
        git checkout -- .
      }
      trap 'restore' ERR

      echo "== setting version to $version =="
      echo "$version" > VERSION

      # VERSION is the single source of truth; every manifest is derived from
      # it. Three files drifting apart is the normal way a polyglot release
      # goes wrong.
      sed -i "s/^version = \".*\"$/version = \"$version\"/" tabular-center-rust/Cargo.toml
      if [ -f tabular-center-kotlin/build.gradle.kts ]; then
        sed -i "s/^version = \".*\"$/version = \"$version\"/" tabular-center-kotlin/build.gradle.kts
      fi

      # Bumping a version stales every Cargo.lock that records it -- including
      # the examples', which pin tabular-center by path. Without this, `--locked` fails
      # everywhere and the error names the lockfile rather than the bump.
      echo "== refreshing lockfiles =="
      (cd tabular-center-rust && cargo update --workspace --offline)
      (cd tabular-center-rust/examples && cargo update --workspace --offline)
      # The GUI example has its own package and lock, outside that workspace.
      # Not `cargo update`: that re-resolves iced's whole tree, offline, from
      # whatever this host has cached. A path dependency's lock entry is just
      # its name and version, so edit exactly that line.
      sed -i "/^name = \"tabular-center\"$/{n;s/^version = \".*\"$/version = \"$version\"/}" \
        tabular-center-rust/examples/05-iced/Cargo.lock

      # `nix flake check`, not the host's `tools/verify`: the definition of
      # green is what CI runs, in the sandbox, with the GUI example's vendored
      # crates and its toolchain, and the Swift checks built rather than
      # skipped. The host run was an approximation that depended on what the
      # host had cached -- rust-gui failed offline on a crate missing from
      # ~/.cargo while `nix flake check` passed. Nix reads tracked files with
      # their uncommitted changes, so this checks the bumped tree.
      echo "== verifying: nix flake check =="
      nix flake check --print-build-logs

      echo "== committing and tagging =="
      trap - ERR
      git add -A
      git commit -m "release: $version"
      git tag -a "v$version" -m "tabular-center $version"

      echo
      echo "tagged v$version. Nothing has been pushed or published."
      echo "  git push --follow-tags"
      echo "  nix run .#publish -- --execute"
    '';
  };

  publish = pkgs.writeShellApplication {
    name = "tabular-center-publish";
    runtimeInputs = commonInputs ++ rustInputs ++ kotlinInputs ++ swiftInputs;
    text = ''
      # `--only rust|kotlin|swift` publishes one ecosystem, so CI can give each
      # job exactly one registry's credentials (.github/workflows/publish.yml).
      # Default: all three, as before.
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

      # See RELEASING.md for why each language ships the artifacts it does.
      if want rust; then
      echo "== rust: crates.io =="
      # One crate. `transition_matrix!` is macro_rules, which ships inside the
      # library it is declared in, so there is nothing to separate. The
      # conformance harness and the examples are publish = false.
      if [ "$execute" -eq 1 ]; then
        (cd tabular-center-rust && cargo publish -p tabular-center)   # needs CARGO_REGISTRY_TOKEN
      else
        (cd tabular-center-rust && cargo publish -p tabular-center --dry-run)
      fi
      fi

      if want kotlin; then
      ${lib.optionalString has.kotlinGradle ''
        echo "== kotlin: maven =="
        # Five artifacts, because they have different scopes: core is
        # `implementation`, annotations `compileOnly`, ksp `ksp`, testing
        # `testImplementation`. Publishing one fat jar would force every
        # consumer to take a processor and a fixture parser into production.
        for m in tabular-center-core tabular-center-annotations tabular-center-codegen tabular-center-ksp tabular-center-testing; do
          echo "  -> $m"
          if [ "$execute" -eq 1 ]; then
            (cd tabular-center-kotlin && gradle --no-daemon ":$m:publish")
          else
            (cd tabular-center-kotlin && gradle --no-daemon ":$m:publishToMavenLocal")
          fi
        done
      ''}
      ${lib.optionalString (!has.kotlinGradle) ''
        echo "== kotlin: skipped =="
        echo "  no Gradle build yet; the artifacts compile with kotlinc alone."
        echo "  planned: tabular-center-core, -annotations, -codegen, -ksp, -testing"
        echo "  see RELEASING.md"
      ''}

      fi

      if want swift; then
      echo "== swift: mirror, then package index =="
      # No registry: SwiftPM and the Package Index resolve from a git
      # repository with Package.swift at its root, which this one is not. So
      # pushing the tag `release` created is what publishes Swift: it triggers
      # .github/workflows/swift-mirror.yml, which splits tabular-center-swift/
      # into tabula-center/tabular-center-swift and tags it `$version`.
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
