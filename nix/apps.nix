# Runnable entry points.
#
# Split from the checks because they do different things: a check must be
# hermetic and offline, while an app is allowed to touch the network, the git
# index, and a registry token. Keeping them in one file invited confusing one
# for the other.
ctx:

let
  inherit (ctx) pkgs lib has rustInputs kotlinInputs swiftPkgs swiftAvailable commonInputs;

  app = drv: name: description: {
    type = "app";
    program = "${drv}/bin/${name}";
    meta.description = description;
  };

  conformance = pkgs.writeShellApplication {
    name = "tabula-conformance";
    runtimeInputs = commonInputs ++ rustInputs
      ++ lib.optionals has.kotlin kotlinInputs
      ++ lib.optionals (has.swift && swiftAvailable) swiftPkgs;
    text = ''
      ${lib.optionalString has.rustConformance ''
        echo "== rust =="
        ./tools/verify conformance
      ''}
      ${lib.optionalString has.kotlin ''
        echo "== kotlin =="
        ./tools/verify kotlin-conformance
      ''}
      ${lib.optionalString (has.swift && swiftAvailable) ''
        echo "== swift =="
        ./tools/verify swift
      ''}
    '';
  };

  tableDiff = pkgs.writeShellApplication {
    name = "tabula-table-diff";
    runtimeInputs = commonInputs ++ rustInputs;
    text = ''
      cd rust
      cargo run -q -p tabula-conformance --bin table-diff --offline --locked -- "$@"
    '';
  };

  # The docs site. `build` regenerates and renders; `serve` also watches.
  #
  # Jekyll is here rather than in a dev shell because it is the only consumer
  # of it in the repository: adding it to the shells would put Ruby on the path
  # of everyone working on Rust.
  docs = pkgs.writeShellApplication {
    name = "tabula-docs";
    runtimeInputs = commonInputs ++ [ pkgs.jekyll ];
    text = ''
      cmd="''${1:-serve}"

      # Always regenerate first. docs/ is generated from spec/ and serving a
      # stale tree is exactly the failure `tools/verify docs` exists to catch;
      # a preview that shows something the repository does not contain is worse
      # than no preview.
      ./tools/docs

      # The theme is a GitHub Pages built-in and is not in nixpkgs' jekyll, so
      # a local render would die on `theme: jekyll-theme-primer`. Rendering
      # without it is honest about what this is -- a content preview, not a
      # pixel-accurate copy of the published site. The config is overridden
      # rather than edited so docs/_config.yml stays correct for Pages.
      scratch="$(mktemp -d)"
      trap 'rm -rf "$scratch"' EXIT
      grep -v '^theme:' docs/_config.yml > "$scratch/config.yml"

      case "$cmd" in
        build)
          jekyll build --source docs --destination "''${2:-docs/_site}" \
            --config "$scratch/config.yml"
          echo "built into ''${2:-docs/_site}"
          ;;
        serve)
          echo "serving docs/ on http://127.0.0.1:4000 -- content preview;"
          echo "the published site adds the primer theme, which nixpkgs' jekyll lacks."
          jekyll serve --source docs --destination "$scratch/site" \
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
    name = "tabula-verify";
    runtimeInputs = commonInputs ++ rustInputs
      ++ lib.optionals has.kotlin kotlinInputs
      ++ lib.optionals (has.swift && swiftAvailable) swiftPkgs;
    text = ''./tools/verify "$@"'';
  };

  publish = import ./publish.nix ctx;

in
{
  conformance = app conformance "tabula-conformance"
    "Run every implementation against spec/conformance";

  table-diff = app tableDiff "tabula-table-diff"
    "Render a machine's matrix as a diffable grid";

  verify = app verify "tabula-verify"
    "Run the same checks nix flake check runs, without the sandbox";

  docs = app docs "tabula-docs"
    "Regenerate docs/ from spec/ and serve it (nix run .#docs -- build)";

  release = app publish.release "tabula-release"
    "Set the version everywhere, verify, and tag";

  publish = app publish.publish "tabula-publish"
    "Publish every language's package (dry run unless --execute)";

  default = app verify "tabula-verify" "Run the checks";
}
