# Runnable entry points.
#
# Split from the checks because they do different things: a check must be
# hermetic and offline, while an app is allowed to touch the network, the git
# index, and a registry token. Keeping them in one file invited confusing one
# for the other.
#
# The root's own apps. `table-diff`, `gradle-lock` and `swift-lock` belong to
# one language each and come from that language's flake (see ../flake.nix).
ctx:

let
  inherit (ctx) pkgs allInputs allSetup commonInputs;

  # Every app operates on the working tree -- regenerating doc/, running
  # cargo, reading spec/ -- so every one of them assumed it was launched from
  # the repository root. `nix run .#docs` from inside docs/ (as it then was)
  # found that out:
  #
  #   /nix/store/...-tabula-docs/bin/tabula-docs: line 14: ./tools/docs:
  #   No such file or directory
  #
  # Prepended to each app rather than fixed in one of them: the bug was in all
  # four, and only the order people happened to run them kept it hidden.
  cdRoot = ''
    if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
      cd "$root"
    else
      echo "not inside a git checkout of tabular-center; these apps work on the tree" >&2
      exit 1
    fi
  '';

  app = drv: name: description: {
    type = "app";
    program = "${drv}/bin/${name}";
    meta.description = description;
  };

  conformance = pkgs.writeShellApplication {
    name = "tabular-center-conformance";
    runtimeInputs = commonInputs ++ [ pkgs.git ] ++ allInputs;
    text = ''
      ${cdRoot}
      ${allSetup}
      echo "== rust =="
      ./tools/verify conformance
      echo "== kotlin =="
      ./tools/verify kotlin-conformance
      echo "== swift =="
      ./tools/verify swift-conformance
    '';
  };

  # The docs site. `build` regenerates and renders; `serve` also watches.
  #
  # Jekyll is here rather than in a dev shell because it is the only consumer
  # of it in the repository: adding it to the shells would put Ruby on the path
  # of everyone working on Rust.
  docs = pkgs.writeShellApplication {
    name = "tabular-center-docs";
    runtimeInputs = commonInputs ++ [ pkgs.git pkgs.jekyll ];
    text = ''
      ${cdRoot}
      cmd="''${1:-serve}"

      # Always regenerate first. doc/ is generated from spec/ and serving a
      # stale tree is exactly the failure `tools/verify docs` exists to catch;
      # a preview that shows something the repository does not contain is worse
      # than no preview.
      ./tools/docs

      # The theme is a GitHub Pages built-in and is not in nixpkgs' jekyll, so
      # a local render would die on `theme: jekyll-theme-primer`. Rendering
      # without it is honest about what this is -- a content preview, not a
      # pixel-accurate copy of the published site. The config is overridden
      # rather than edited so doc/_config.yml stays as generated.
      scratch="$(mktemp -d)"
      trap 'rm -rf "$scratch"' EXIT
      grep -v '^theme:' doc/_config.yml > "$scratch/config.yml"

      case "$cmd" in
        build)
          jekyll build --source doc --destination "''${2:-doc/_site}" \
            --config "$scratch/config.yml"
          echo "built into ''${2:-doc/_site}"
          ;;
        serve)
          echo "serving doc/ on http://127.0.0.1:4000 -- content preview;"
          echo "the published site adds the primer theme, which nixpkgs' jekyll lacks."
          jekyll serve --source doc --destination "$scratch/site" \
            --config "$scratch/config.yml" --host 127.0.0.1 --port 4000
          ;;
        *)
          echo "usage: nix run .#docs -- [serve|build [dir]]" >&2
          exit 2
          ;;
      esac
    '';
  };

  verify = pkgs.writeShellApplication {
    name = "tabular-center-verify";
    runtimeInputs = commonInputs ++ [ pkgs.git ] ++ allInputs;
    # `allSetup` below exports the Swift runtime path, the way every Swift
    # check does. This app used to put Swift on PATH without it, so a Swift
    # binary it built could not find libdispatch.so. (kotlinc's wrapper
    # already defaults JAVA_HOME to the pinned JDK.)
    text = ''
      ${cdRoot}
      ${allSetup}
      ./tools/verify "$@"
    '';
  };

  publish = import ./publish.nix ctx;

in
{
  conformance = app conformance "tabular-center-conformance"
    "Run every implementation against spec/conformance";

  verify = app verify "tabular-center-verify"
    "Run the same checks nix flake check runs, without the sandbox";

  docs = app docs "tabular-center-docs"
    "Regenerate doc/ and serve it (nix run .#docs -- build)";

  release = app publish.release "tabular-center-release"
    "Set the version everywhere, verify, and tag";

  publish = app publish.publish "tabular-center-publish"
    "Publish every language's package (dry run unless --execute)";

  default = app verify "tabular-center-verify" "Run the checks";
}
