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
  inherit (ctx) pkgs lib has toolchains commonInputs;
  rustInputs = toolchains.rust.inputs;
  kotlinInputs = toolchains.kotlin.inputs;
  # Empty where there is no Swift toolchain, so it can be appended as is.
  swiftInputs = toolchains.swift.inputs;
in
{
  release = pkgs.writeShellApplication {
    name = "tabular-center-release";
    # Rust and Kotlin, as before the split: without Swift on PATH the Swift
    # steps report `skip`, which is what a release run on Linux always did.
    runtimeInputs = commonInputs ++ rustInputs ++ kotlinInputs;
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
      # the examples', which pin tabula by path. Without this, `--locked` fails
      # everywhere and the error names the lockfile rather than the bump.
      echo "== refreshing lockfiles =="
      (cd tabular-center-rust && cargo update --workspace --offline)
      (cd tabular-center-rust/examples && cargo update --workspace --offline)

      echo "== verifying =="
      ./tools/verify

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
      execute=0
      for a in "$@"; do [ "$a" = "--execute" ] && execute=1; done

      version="$(cat VERSION 2>/dev/null || echo unknown)"
      if [ "$execute" -eq 0 ]; then
        echo "DRY RUN for $version. Pass --execute to publish for real."
        echo
      fi

      # See RELEASING.md for why each language ships the artifacts it does.
      echo "== rust: crates.io =="
      # One crate. `transition_matrix!` is macro_rules, which ships inside the
      # library it is declared in, so there is nothing to separate. The
      # conformance harness and the examples are publish = false.
      if [ "$execute" -eq 1 ]; then
        (cd tabular-center-rust && cargo publish -p tabula)   # needs CARGO_REGISTRY_TOKEN
      else
        (cd tabular-center-rust && cargo publish -p tabula --dry-run)
      fi

      ${lib.optionalString has.kotlinGradle ''
        echo "== kotlin: maven =="
        # Five artifacts, because they have different scopes: core is
        # `implementation`, annotations `compileOnly`, ksp `ksp`, testing
        # `testImplementation`. Publishing one fat jar would force every
        # consumer to take a processor and a fixture parser into production.
        for m in tabula-core tabula-annotations tabula-codegen tabula-ksp tabula-testing; do
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
        echo "  planned: tabula-core, -annotations, -codegen, -ksp, -testing"
        echo "  see RELEASING.md"
      ''}

      echo "== swift: package index =="
      # No registry: the Package Index resolves from git tags, so publishing is
      # pushing the tag `release` created. The three products (Tabula,
      # TabulaMacros, TabulaTesting) ship from one repository by definition.
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
