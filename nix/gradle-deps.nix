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
  # Rooted at the repository, not at the example.
  #
  # `settings.gradle.kts` reaches the processor with `../../../kotlin/ksp`, and
  # a source rooted at the example puts that path outside the unpacked tree:
  #
  #   Included build '/nix/var/nix/kotlin/ksp' does not exist.
  #
  # The climb is correct in the repository and meaningless in a store path that
  # begins below it. Rooting higher is the fix; the fileset keeps it to the four
  # files that decide what gets resolved, so editing a `.kt` still does not
  # re-resolve the world.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../examples/kotlin/06-generated/build.gradle.kts
      ../examples/kotlin/06-generated/settings.gradle.kts
      ../kotlin/ksp/build.gradle.kts
    ];
  };

  nativeBuildInputs = [ pkgs.gradle jdk pkgs.cacert pkgs.curl ];

  # TLS certificates, and the reason the first two attempts failed.
  #
  # A fixed-output derivation is allowed network access, and this one had it.
  # What it did not have was a CA bundle: the sandbox starts from nothing, so
  # every HTTPS connection failed the handshake. Gradle reports that as
  #
  #   could not resolve plugin artifact ...
  #     Searched in the following repositories:
  #       Gradle Central Plugin Repository
  #       MavenRepo
  #
  # which reads like "the artifact is not there" and means "I could not talk to
  # anything". Adding mavenCentral() to pluginManagement was therefore a correct
  # change that could not possibly have fixed it -- a second repository it was
  # equally unable to reach.
  SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  # Proxies are the other thing a sandboxed fetch needs and cannot infer.
  # `proxyImpureEnvVars` is the standard list; without it a machine behind a
  # proxy fails here in exactly the way this derivation just did, and with
  # exactly as little explanation.
  impureEnvVars = lib.fetchers.proxyImpureEnvVars;

  buildPhase = ''
    export GRADLE_USER_HOME="$PWD/.gradle-home"
    # The Gradle build lives here; the source root is the repository so that
    # settings.gradle.kts can climb to the processor.
    cd examples/kotlin/06-generated

    # Probe before building, because three attempts at this derivation failed
    # with the same Gradle message -- "could not resolve plugin artifact",
    # having searched two repositories -- and that message cannot distinguish
    # between "the artifact is missing", "TLS failed", and "there is no
    # network". Two fixes were made on the strength of guessing which, and
    # neither changed the outcome.
    #
    # So: ask directly, and put the answer in the log. `|| true` because the
    # probe is diagnostic and must not replace Gradle's own failure with a
    # different one.
    echo "--- connectivity probe ---"
    curl -sS -o /dev/null -w 'plugins.gradle.org  http=%{http_code}  err=%{errormsg}\n' \
      https://plugins.gradle.org/m2/ || true
    curl -sS -o /dev/null -w 'repo1.maven.org    http=%{http_code}  err=%{errormsg}\n' \
      https://repo1.maven.org/maven2/ || true
    echo "SSL_CERT_FILE=$SSL_CERT_FILE"
    echo "--- end probe ---"

    # --no-daemon because a daemon outlives the build and writes to paths the
    # sandbox will not have; --console=plain so the output is readable in a log
    # rather than a progress animation replayed as thousands of lines.
    # --stacktrace, because "could not resolve plugin artifact" is Gradle's
    # summary of a cause it does not print. The probe above proves the sandbox
    # reaches both repositories over TLS, so whatever stops Gradle is inside
    # Gradle, and four patches have now been spent on the summary line.
    #
    # The JVM is the live suspect: curl honours SSL_CERT_FILE and the JVM does
    # not -- it reads its own truststore -- so a build can sit in a sandbox
    # with working TLS and still fail every HTTPS connection. Not guessed at
    # here, because guessing is what the last four patches were. The stacktrace
    # will name the cause, and the fix follows from the name.
    gradle --no-daemon --console=plain --stacktrace \
      -Dorg.gradle.internal.repository.max.retries=1 \
      :processor:dependencies --configuration compileClasspath
  '';

  installPhase = ''
    # Only the artifacts. Gradle's home also holds daemon logs, caches keyed by
    # absolute path, and `.lock` files -- all of which differ between runs and
    # would make the output hash unstable, which is the usual reason a
    # fixed-output Gradle derivation fails to reproduce.
    mkdir -p "$out"
    cp -r examples/kotlin/06-generated/.gradle-home/caches/modules-2 "$out/" \
      2>/dev/null || true
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
