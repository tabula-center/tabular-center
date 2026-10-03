# The Kotlin half of `nix flake check`.
#
# Every check shells out to `tabular-center-kotlin/tools/verify <step>`, the
# same script `./tools/verify` at the root hands Kotlin steps to. The names are
# the ones the single root flake used.
ctx:

let
  inherit (ctx) kotlinInputs gradleRepo mkCheck;
  verify = name: mkCheck name kotlinInputs "./tabular-center-kotlin/tools/verify ${name}";

  # The KSP checks resolve Gradle against the offline repository nix builds
  # from the lock. They EXIST without the lock, and fail with the command that
  # fixes it: a check that is absent from the attribute set cannot report that
  # it is absent, and `nix flake check` would print a tidy green summary over
  # a KSP example nobody built -- which is how the Kotlin suite went unrun for
  # months (PLAN 0c) and what 0d decided not to repeat.
  withRepo = name: detail:
    if gradleRepo != null
    then
      mkCheck name kotlinInputs ''
        # Exported rather than guessed at by the script: nix built the
        # directory and knows where it is.
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
  # Guards the matrix alignment against ktlint's formatter -- narrowly, without
  # adopting ktlint as a style gate. See the backlog entry in PLAN.md.
  kotlin-matrix-stable = verify "kotlin-matrix-stable";

  # The annotation processor, running. Its own check rather than part of
  # `kotlin-examples`, because it is the one Kotlin step whose inputs are not
  # just source: a failure here means a stale lock or a broken processor, and
  # burying that in the examples step would make it read as an example being
  # broken.
  kotlin-ksp = withRepo "kotlin-ksp" "tabular-center-kotlin/examples/06-generated";
  kotlin-ksp-compile-fail = withRepo "kotlin-ksp-compile-fail" "the KSP compile-fail fixtures";
  kotlin-ksp-incremental = withRepo "kotlin-ksp-incremental" "the incremental-KSP experiment";

  # The Compose Desktop example. The step itself skips, loudly, when the
  # locked artifact set predates Compose.
  kotlin-compose = withRepo "kotlin-compose" "tabular-center-kotlin/examples/07-compose";

  # The Maven Central bundle, built offline and checked against Central's
  # rules: withRepo's artifact set, plus gpg (for gpgv and --dearmor) and zip.
  kotlin-publication =
    if gradleRepo != null
    then
      mkCheck "kotlin-publication" (kotlinInputs ++ [ ctx.pkgs.gnupg ctx.pkgs.zip ctx.pkgs.unzip ]) ''
        export TABULAR_CENTER_MAVEN_REPO="${gradleRepo}"
        ./tabular-center-kotlin/tools/verify kotlin-publication
      ''
    else withRepo "kotlin-publication" "the Maven Central bundle";
}
