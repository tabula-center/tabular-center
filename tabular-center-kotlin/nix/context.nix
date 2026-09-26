# The Kotlin toolchain and the check builder, per system. Threaded through the
# other modules in this directory as `ctx`.
{ self, system, nixpkgs }:

let
  pkgs = import nixpkgs { inherit system; };
  inherit (pkgs) lib;

  # The whole repository, not just this directory: the checks run
  # `tabular-center-kotlin/tools/verify` from the root, and read spec/ and
  # examples/kotlin. See the same binding in
  # ../../tabular-center-rust/nix/context.nix for why `self.sourceInfo` and
  # why it is checked.
  root =
    let r = self.sourceInfo.outPath; in
    if builtins.pathExists (r + "/spec/conformance")
    then r
    else
      throw ''
        tabular-center-kotlin: this flake's source is not the whole repository,
        so spec/ and examples/ are out of reach. Check it from a git checkout
        (`nix flake check ./tabular-center-kotlin`), or through the root flake,
        with Nix 2.26 or later.
      '';

  has = {
    # The KSP example can build offline exactly when the lock exists. Gating
    # on the lock rather than on `gradle` being installed is the whole point:
    # gradle is always present in these checks -- kotlinInputs ships it -- and
    # what was ever missing is the artifacts.
    gradleLock = builtins.pathExists ./gradle-lock.json;
  };

  # The offline Maven repository, or null when nothing has been locked yet.
  gradleRepo =
    if has.gradleLock
    then import ./gradle-repo.nix { inherit pkgs lib; lockFile = ./gradle-lock.json; }
    else null;

  jdk = pkgs.jdk21;

  # kotlinc, pinned to the SAME version as everything else Kotlin here.
  #
  # This was `pkgs.kotlin`, which is whatever the nixpkgs channel ships. The
  # rest of the repository says 2.1.20 in four places -- both Gradle builds'
  # `kotlin("jvm")`, the KSP pair `2.1.20-1.0.32`, ci.yml's check-no-nix
  # download, and tabular-center-kotlin/README.md's "verified against kotlinc 2.1.20" -- and
  # the flake alone floated. Moving `nixpkgs` from 25.05 to 26.05 for Swift
  # therefore moved the Kotlin compiler as a side effect, which is the exact
  # shape 0c warned about: a change to one language's toolchain landing in
  # another's checks.
  #
  # It matters more for Kotlin than for most compilers because four fixtures
  # assert on kotlinc's own message text (`//~ EXPECT:` in compile_fail/), and
  # that text is the compiler's, not ours -- spec/diagnostics.md says so and
  # says it must not be normalised. A compiler upgrade is allowed to reword
  # it; the fixtures should move when WE move the compiler, on purpose.
  #
  # Owned rather than overridden: `pkgs.kotlin.overrideAttrs` would depend on
  # the shape of nixpkgs' installPhase for a release it was not written for.
  # The distribution is a zip of shell scripts and jars; wrapping it is five
  # lines. Bump `kotlinVersion` and the hash together, and the two Gradle
  # builds and ci.yml with them.
  kotlinVersion = "2.1.20";
  kotlinc = pkgs.stdenvNoCC.mkDerivation {
    pname = "kotlinc";
    version = kotlinVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/JetBrains/kotlin/releases/download/v${kotlinVersion}/kotlin-compiler-${kotlinVersion}.zip";
      hash = "sha256-oRgZew3lX/qyvI1c0DpeOQM8+1M4PWkxvHYd7AeEiRo=";
    };
    nativeBuildInputs = [ pkgs.unzip pkgs.makeWrapper ];
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      rm -f bin/*.bat
      mkdir -p "$out"
      cp -r . "$out/"
      # The scripts find java through JAVA_HOME or PATH. mkCheck sets
      # JAVA_HOME already; --set-default keeps a dev shell with its own
      # JAVA_HOME in charge, and gives a bare `nix shell` a working default.
      for p in "$out"/bin/*; do
        wrapProgram "$p" --set-default JAVA_HOME "${jdk}" --prefix PATH : "${jdk}/bin"
      done
      runHook postInstall
    '';
  };

  kotlinInputs = [ jdk pkgs.gradle kotlinc pkgs.ktlint ];
  commonInputs = [ pkgs.git pkgs.jq pkgs.just pkgs.graphviz pkgs.nixpkgs-fmt ];

  mkCheck = name: inputs: script:
    pkgs.runCommand "tabular-center-check-${name}"
      {
        nativeBuildInputs = commonInputs ++ inputs;

        # kotlinc and ktlint are both JVM programs that look for a JDK. The
        # nixpkgs wrappers usually carry one, but "usually" is a guess and nix
        # knows the answer.
        JAVA_HOME = "${jdk}";
      }
      ''
        export HOME="$TMPDIR/home"
        export GRADLE_USER_HOME="$TMPDIR/gradle"

        # The sandbox has no network, and the steps that need one must SKIP
        # rather than fail. Stated, not detected: tools/verify reads it, and
        # it is unset everywhere else, so ci.yml's check-no-nix job -- which
        # HAS Maven -- still runs the Gradle and KSP path online.
        export TABULAR_CENTER_OFFLINE=1

        mkdir -p "$HOME" "$GRADLE_USER_HOME"

        cp -r ${root} src && chmod -R u+w src && cd src
        ${script}
        touch $out
      '';

  mkShell = name: extra: pkgs.mkShell {
    inherit name;
    packages = commonInputs ++ extra;
    JAVA_HOME = "${jdk}";
    GRADLE_USER_HOME = "./.gradle-home";
    shellHook = ''
      echo "tabular-center :: ${name}"
    '';
  };

in
{
  inherit self system pkgs lib has root jdk kotlinc kotlinVersion kotlinInputs
    commonInputs gradleRepo mkCheck mkShell;

  # For the root flake. See `legacyPackages` in ../flake.nix.
  toolchain = {
    inputs = kotlinInputs;
    env = { JAVA_HOME = "${jdk}"; };
    setup = "";
    available = true;
  };
}
