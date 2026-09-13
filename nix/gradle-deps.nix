# Gradle dependencies, fetched once and pinned by hash.
#
# `nix flake check` has no network, and `examples/kotlin/06-generated` needs
# KSP from Maven. Skipping it was not acceptable and did not need to be: this
# is the ordinary Nix answer for a build that fetches, the same shape as
# `cargoDeps` or `vendorHash`.
#
# A fixed-output derivation is the one kind of derivation allowed to reach the
# network, in exchange for declaring what it will produce. `gradle` runs here
# with its own `GRADLE_USER_HOME`, the resolved artifacts are captured, and the
# hash pins them. Afterwards the real build runs offline against that store
# path, so the check is reproducible and the network is used once per dependency
# change rather than once per build.
{ pkgs, lib, jdk }:

pkgs.stdenv.mkDerivation {
  pname = "tabula-gradle-deps";
  version = "0.1.0";

  # Only the files that determine what gets resolved. Including the sources
  # would rebuild the whole dependency set on every edit to a `.kt` file, which
  # is the difference between a cache and a tax.
  src = lib.fileset.toSource {
    root = ../examples/kotlin/06-generated;
    fileset = lib.fileset.unions [
      ../examples/kotlin/06-generated/build.gradle.kts
      ../examples/kotlin/06-generated/settings.gradle.kts
    ];
  };

  nativeBuildInputs = [ pkgs.gradle jdk ];

  buildPhase = ''
    export GRADLE_USER_HOME="$PWD/.gradle-home"
    # --no-daemon because a daemon outlives the build and writes to paths the
    # sandbox will not have; --console=plain so the output is readable in a log
    # rather than a progress animation replayed as thousands of lines.
    gradle --no-daemon --console=plain \
      -Dorg.gradle.internal.repository.max.retries=1 \
      :processor:dependencies --configuration compileClasspath
  '';

  installPhase = ''
    # Only the artifacts. Gradle's home also holds daemon logs, caches keyed by
    # absolute path, and `.lock` files -- all of which differ between runs and
    # would make the output hash unstable, which is the usual reason a
    # fixed-output Gradle derivation fails to reproduce.
    mkdir -p "$out"
    cp -r .gradle-home/caches/modules-2 "$out/" 2>/dev/null || true
    find "$out" -name '*.lock' -delete
    find "$out" -name 'gc.properties' -delete
  '';

  # Fixed-output: this is what makes network access legal here.
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  # PLACEHOLDER. Nothing in this environment can reach Maven, so this hash was
  # not computed -- it was written. The first build will fail with the real one:
  #
  #   error: hash mismatch in fixed-output derivation
  #          specified: sha256-AAAA...
  #          got:       sha256-<the real hash>
  #
  # Paste the `got` value here. That is the normal workflow for a fixed-output
  # derivation, not a workaround, and it is why the placeholder is all zeroes
  # rather than a plausible-looking string that might be mistaken for real.
  outputHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
}
