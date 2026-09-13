// UNVERIFIED. Written from the KSP documentation, never run -- Gradle needs
// Maven Central and this environment cannot reach it. See README.md.
//
// Reviewed once against the tree without running it, in the same pass that
// reviewed the processor. One near-certain bug came out of that and is fixed
// below; the rest is still documentation-shaped rather than evidence-shaped.
plugins {
    kotlin("jvm") version "2.1.20"
}

// A coordinate, so a consuming build can substitute this project for it.
// Nothing publishes to it; it exists to be named. See
// examples/kotlin/06-generated/settings.gradle.kts.
group = "dev.tabula"
version = "0.1.0"

repositories { mavenCentral() }

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
