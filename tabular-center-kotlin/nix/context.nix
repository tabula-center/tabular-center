# The Kotlin toolchain and the check builder, per system, threaded through
# this directory as `ctx`: the pinned JDK, kotlinc (owned, pinned to the
# version the Gradle builds use), ktlint, Gradle confined to that JDK, and the
# offline Maven repository when its lock exists. A check sees this directory,
# spec/, .editorconfig and VERSION. ARCHITECTURE.md 16, "Nix: Kotlin".
{ self, system, nixpkgs }:

let
  pkgs = import nixpkgs { inherit system; };
  inherit (pkgs) lib;

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
  versionFile = builtins.path { path = fromCheckout ../../VERSION; name = "tabular-center-version"; };
  langSrc = builtins.path { path = ./..; name = "tabular-center-kotlin-src"; };

  has = {
    gradleLock = builtins.pathExists ./gradle-lock.json;
  };

  gradleRepo =
    if has.gradleLock
    then import ./gradle-repo.nix { inherit pkgs lib; lockFile = ./gradle-lock.json; }
    else null;

  jdk = pkgs.jdk21;

  jdkHome = jdk.home or "${jdk}";

  kotlinVersion = "2.4.21";
  kotlinc = pkgs.stdenvNoCC.mkDerivation {
    pname = "kotlinc";
    version = kotlinVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/JetBrains/kotlin/releases/download/v${kotlinVersion}/kotlin-compiler-${kotlinVersion}.zip";
      hash = "sha256-fMFA522vQWoEJKVVf5mv18qJ69Rj6hEBJh4+AcM+dc0=";
    };
    nativeBuildInputs = [ pkgs.unzip pkgs.makeWrapper ];
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      rm -f bin/*.bat
      mkdir -p "$out"
      cp -r . "$out/"
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

        JAVA_HOME = jdkHome;
      }
      ''
        export HOME="$TMPDIR/home"
        export GRADLE_USER_HOME="$TMPDIR/gradle"

        export TABULAR_CENTER_OFFLINE=1

        mkdir -p "$HOME" "$GRADLE_USER_HOME"

        cat > "$GRADLE_USER_HOME/gradle.properties" <<PROPS
        org.gradle.java.home=${jdkHome}
        org.gradle.java.installations.paths=${jdkHome}
        org.gradle.java.installations.auto-detect=false
        org.gradle.java.installations.auto-download=false
        PROPS

        mkdir src
        cp -r ${specSrc} src/spec
        cp -r ${langSrc} src/tabular-center-kotlin
        cp ${editorconfig} src/.editorconfig
        cp ${versionFile} src/VERSION
        chmod -R u+w src && cd src

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
      export GRADLE_USER_HOME="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/tabular-center-kotlin/.gradle-home"
    '';
  };

in
{
  inherit self system pkgs lib has specSrc langSrc editorconfig jdk jdkHome kotlinc kotlinVersion kotlinInputs
    commonInputs gradleRepo mkCheck mkShell;

  toolchain = {
    inputs = kotlinInputs;
    env = { JAVA_HOME = jdkHome; };
    setup = "";
    available = true;
  };
}
