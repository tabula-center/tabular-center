// The processor's build. It runs: `nix flake check` builds it as an included
// build of tabular-center-kotlin/examples/06-generated (the `kotlin-ksp` check), resolving
// from the artifact set pinned in nix/gradle-lock.json. See README.md.
//
// Written from the KSP documentation before it could run, and reviewed by
// reading first; the one bug that review found is recorded below.
plugins {
    kotlin("jvm") version "2.1.20"
}

// A coordinate, so a consuming build can substitute this project for it.
// Nothing publishes to it; it exists to be named. See
// tabular-center-kotlin/examples/06-generated/settings.gradle.kts.

// Same TABULAR_CENTER_MAVEN_REPO switch as the example. This is an included build, so
// it resolves independently -- its own pluginManagement lives in the
// settings.gradle.kts next to this file.
val tabulaRepo: String? = System.getenv("TABULAR_CENTER_MAVEN_REPO")?.takeIf { it.isNotBlank() }

repositories {
    if (tabulaRepo != null) maven { url = uri(tabulaRepo) } else mavenCentral()
}

dependencies {
    implementation("com.google.devtools.ksp:symbol-processing-api:2.1.20-1.0.32")
}

// The generator's logic lives in ../codegen and is compiled with kotlinc alone
// everywhere else; this module is only the KSP adapter over it.
//
// This used to read `implementation(files("../codegen"))`, which would not have
// worked: `files()` puts a path on the compile classpath as a directory of
// *class* files, and ../codegen holds .kt sources. Every `import codegen.*` in
// TabularCenterProcessor.kt would have failed to resolve.
//
// Compiled as sources instead, with the rest of that directory excluded.
// `srcDir` takes a directory, not a file list, so the filtering is done with
// exclude patterns: Main.kt is a CLI entry point, Tests.kt is the golden-diff
// suite and reads paths relative to the repository root, and compile_fail/
// holds fixtures that are *supposed* not to compile.
sourceSets["main"].kotlin {
    srcDir("../codegen")
    exclude("Main.kt", "Tests.kt", "compile_fail/**", "golden/**", "support/**")
}

kotlin { jvmToolchain(21) }

// Coordinates (group center.tabula, the version from VERSION), the POM and
// signing: shared with the other four artifacts. Inert unless staging.
apply(from = "../gradle/publication.gradle.kts")
