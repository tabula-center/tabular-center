// The processor's build. It runs: `nix flake check` builds it as an included
// build of examples/kotlin/06-generated (the `kotlin-ksp` check), resolving
// from the artifact set pinned in nix/gradle-lock.json. See README.md.
//
// Written from the KSP documentation before it could run, and reviewed by
// reading first; the one bug that review found is recorded below.
plugins {
    kotlin("jvm") version "2.1.20"
}

// A coordinate, so a consuming build can substitute this project for it.
// Nothing publishes to it; it exists to be named. See
// examples/kotlin/06-generated/settings.gradle.kts.
group = "dev.tabula"
version = "0.1.0"

// Same TABULA_MAVEN_REPO switch as the example. This is an included build, so
// it resolves independently -- its own pluginManagement lives in the
// settings.gradle.kts next to this file.
val tabulaRepo: String? = System.getenv("TABULA_MAVEN_REPO")?.takeIf { it.isNotBlank() }

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
// TabulaProcessor.kt would have failed to resolve.
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
