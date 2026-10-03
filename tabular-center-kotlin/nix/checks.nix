# The Kotlin half of `nix flake check`: one check per
# `tabular-center-kotlin/tools/verify` step, named kotlin-<step>. The KSP,
# Compose and publication checks resolve Gradle against the offline
# repository built from nix/gradle-lock.json, and fail naming
# `nix run .#gradle-lock` when it is missing.
ctx:

let
  inherit (ctx) kotlinInputs gradleRepo mkCheck;
  verify = name: mkCheck name kotlinInputs "./tabular-center-kotlin/tools/verify ${name}";

  withRepo = name: detail:
    if gradleRepo != null
    then
      mkCheck name kotlinInputs ''
        export TABULAR_CENTER_MAVEN_REPO="${gradleRepo}"
        ./tabular-center-kotlin/tools/verify ${name}
      ''
    else
      mkCheck name [ ] ''
        cat <<'MSG'
        ${name}: tabular-center-kotlin/nix/gradle-lock.json does not exist, so
        there is no artifact set to build ${detail} against.

        Bootstrap it once, on a machine with network:

            nix run .#gradle-lock

        then commit the lock. After that every `nix flake check` builds it
        offline against pinned hashes.

        This check fails rather than disappearing on purpose. A missing check
        looks exactly like a passing one in `nix flake check` output.
        MSG
        exit 1
      '';
in
{
  kotlin = verify "kotlin";
  kotlin-compile-fail = verify "kotlin-compile-fail";
  kotlin-conformance = verify "kotlin-conformance";
  kotlin-codegen = verify "kotlin-codegen";
  kotlin-examples = verify "kotlin-examples";
  kotlin-matrix-stable = verify "kotlin-matrix-stable";

  kotlin-ksp = withRepo "kotlin-ksp" "tabular-center-kotlin/examples/06-generated";
  kotlin-ksp-compile-fail = withRepo "kotlin-ksp-compile-fail" "the KSP compile-fail fixtures";
  kotlin-ksp-incremental = withRepo "kotlin-ksp-incremental" "the incremental-KSP experiment";

  kotlin-compose = withRepo "kotlin-compose" "tabular-center-kotlin/examples/07-compose";

  kotlin-publication =
    if gradleRepo != null
    then
      mkCheck "kotlin-publication" (kotlinInputs ++ [ ctx.pkgs.gnupg ctx.pkgs.zip ctx.pkgs.unzip ]) ''
        export TABULAR_CENTER_MAVEN_REPO="${gradleRepo}"
        ./tabular-center-kotlin/tools/verify kotlin-publication
      ''
    else withRepo "kotlin-publication" "the Maven Central bundle";
}
