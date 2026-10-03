# The root's runnable entry points: `nix run .#verify` (every tools/verify
# step), `.#docs [serve|build]`, `.#conformance`, and `.#release` and
# `.#publish` from publish.nix. Apps run on the host and may touch the
# network, the git index and the working tree; checks may not. Each starts at
# the repository root. table-diff, bench, gradle-lock and swift-lock belong to one
# language and come from that language's flake.
ctx:

let
  inherit (ctx) pkgs toolchains allInputs allSetup commonInputs;

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

  docs = pkgs.writeShellApplication {
    name = "tabular-center-docs";
    runtimeInputs = commonInputs ++ [ pkgs.git pkgs.jekyll ];
    text = ''
      ${cdRoot}
      cmd="''${1:-serve}"

      ./tools/docs

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
    text = ''
      ${cdRoot}
      ${allSetup}
      export JAVA_HOME="${toolchains.kotlin.env.JAVA_HOME}"
      export TABULAR_CENTER_JDK_HOME="${toolchains.kotlin.env.JAVA_HOME}"
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
