# The Kotlin toolchain and the check builder, per system. Threaded through the
# other modules in this directory as `ctx`.
{ self, system, nixpkgs }:

let
  pkgs = import nixpkgs { inherit system; };
  inherit (pkgs) lib;

  # What a check is given, each part its own store path.
  #
  # The checks run `tabular-center-kotlin/tools/verify` from a copy of the
  # repository's layout holding three things: this directory, spec/ (the
  # conformance contract, the one input all three languages share by design)
  # and .editorconfig. Each is copied into the store separately with
  # `builtins.path`, so each is hashed by its own contents -- and a check's
  # inputs are exactly those three and its toolchain. Editing Kotlin does not
  # rebuild a Rust check; editing spec/ rebuilds all three, as it should.
  #
  # It used to copy `self.sourceInfo` -- the whole checkout, one store path --
  # so every commit anywhere rebuilt every check, even after each check had
  # been trimmed to read only its own subtree. Reading less is what makes a
  # check independent; depending on less is what makes it cheap.
  #
  # `../../spec` reaches above this flake's directory. That works exactly when
  # the flake's source is the whole checkout: checked from git
  # (`nix flake check ./tabular-center-kotlin`, which nix treats as `?dir=`) or
  # composed by the root flake as a relative `path:` input (Nix 2.26 or later).
  # Asked first, through `self.sourceInfo`, so any other way in gets this
  # message rather than an "access to absolute path is forbidden" from
  # whichever file happened to be read first.
  wholeCheckout = builtins.pathExists (self.sourceInfo.outPath + "/spec/conformance");
  fromCheckout = path:
    if wholeCheckout
    then path
    else
      throw ''
        tabular-center-kotlin: this flake's source is not the whole repository,
        so spec/ is out of reach. Check it from a git checkout
        (`nix flake check ./tabular-center-kotlin`), or through the root flake,
        with Nix 2.26 or later.
      '';

  specSrc = builtins.path { path = fromCheckout ../../spec; name = "tabular-center-spec"; };
  editorconfig = builtins.path { path = fromCheckout ../../.editorconfig; name = "tabular-center-editorconfig"; };
  langSrc = builtins.path { path = ./..; name = "tabular-center-kotlin-src"; };

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

  # The Java home, which is not always the package root. On Linux the root
  # happens to have a working bin/java; on Darwin the JDK lives under
  # `.../Contents/Home`, so JAVA_HOME set to the root is not a JDK at all --
  # and Gradle, handed a JAVA_HOME that is not one, goes looking for a JVM by
  # itself. nixpkgs' JDKs say where home is.
  jdkHome = jdk.home or "${jdk}";

  # kotlinc, pinned to the SAME version as everything else Kotlin here.
  #
  # This was `pkgs.kotlin`, which is whatever the nixpkgs channel ships. The
  # rest of the repository says 2.1.20 in three places -- both Gradle builds'
  # `kotlin("jvm")`, the KSP pair `2.1.20-1.0.32`, and tabular-center-kotlin/README.md's "verified against kotlinc 2.1.20" -- and
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
        wrapProgram "$p" --set-default JAVA_HOME "${jdkHome}" --prefix PATH : "${jdk}/bin"
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
        JAVA_HOME = jdkHome;
      }
      ''
        export HOME="$TMPDIR/home"
        export GRADLE_USER_HOME="$TMPDIR/gradle"

        # The sandbox has no network, and the steps that need one must SKIP
        # rather than fail. Stated, not detected: tools/verify reads it, and
        # it is unset everywhere else, so a developer running tools/verify
        # without nix -- who HAS Maven -- still gets the Gradle and KSP path,
        # online.
        export TABULAR_CENTER_OFFLINE=1

        mkdir -p "$HOME" "$GRADLE_USER_HOME"

        # Our JDK is the only JVM Gradle may use, for the daemon and for
        # `jvmToolchain(21)` alike.
        #
        # Nix pins the JDK; it does not pin which JVM Gradle picks. Left to
        # itself Gradle AUTO-DETECTS installations, and the Darwin sandbox is
        # not sealed the way Linux's is: on a GitHub macOS runner it found the
        # runner's own JDK 17, which then loaded a KSP processor compiled by
        # our 21 -- "class file version 65.0 ... only recognizes up to 61.0".
        # Same flake.lock, different JVM, because the choice was never locked.
        #
        # In GRADLE_USER_HOME's gradle.properties, which outranks the
        # project's: the store path exists only here, so nothing committed
        # names one, and a build outside nix keeps choosing for itself.
        cat > "$GRADLE_USER_HOME/gradle.properties" <<PROPS
        org.gradle.java.home=${jdkHome}
        org.gradle.java.installations.paths=${jdkHome}
        org.gradle.java.installations.auto-detect=false
        org.gradle.java.installations.auto-download=false
        PROPS

        # This directory, spec/, and .editorconfig -- laid out as in the
        # repository, and nothing else. tools/verify runs from the repository
        # root and names paths from there, so the layout is kept; what is left
        # out is the other two languages and the root's own files. A step that
        # reached into either would fail here rather than quietly working,
        # which is what makes "independent" a checked property instead of a
        # claim. spec/ is the one thing all three share by design: it is the
        # cross-language contract.
        mkdir src
        cp -r ${specSrc} src/spec
        cp -r ${langSrc} src/tabular-center-kotlin
        cp ${editorconfig} src/.editorconfig
        chmod -R u+w src && cd src

        # Every script here starts `#!/usr/bin/env bash`, and the build
        # sandbox has no /usr/bin/env: on a strict sandbox (CI) the first step
        # died "bad interpreter", while a local nix with the sandbox relaxed
        # saw the host's /usr/bin/env and passed. patchShebangs points each
        # shebang at the store's bash -- the verify scripts, and every script
        # they call by path (compile-fail, the language scripts the root hands
        # steps to) -- so the check no longer depends on the host at all.
        patchShebangs --build . >/dev/null
        ${script}
        touch $out
      '';

  mkShell = name: extra: pkgs.mkShell {
    inherit name;
    packages = commonInputs ++ extra;
    JAVA_HOME = jdkHome;
    shellHook = ''
      echo "tabular-center :: ${name}"
      # Gradle's cache, kept with the Kotlin it serves. It was
      # `./.gradle-home`, relative to wherever `nix develop` was typed, so it
      # landed at the repository root -- or in whichever subdirectory you
      # happened to be in -- and the root carried a Kotlin-only directory.
      # Anchored to the checkout instead, so every shell finds the same one.
      export GRADLE_USER_HOME="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/tabular-center-kotlin/.gradle-home"
    '';
  };

in
{
  inherit self system pkgs lib has specSrc langSrc editorconfig jdk jdkHome kotlinc kotlinVersion kotlinInputs
    commonInputs gradleRepo mkCheck mkShell;

  # For the root flake. See `legacyPackages` in ../flake.nix.
  toolchain = {
    inputs = kotlinInputs;
    env = { JAVA_HOME = jdkHome; };
    setup = "";
    available = true;
  };
}
