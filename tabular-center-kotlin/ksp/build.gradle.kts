// The processor's build. It runs: `nix flake check` builds it as an included
// build of tabular-center-kotlin/examples/06-generated (the `kotlin-ksp` check), resolving
// from the artifact set pinned in nix/gradle-lock.json. See README.md.
//
// Written from the KSP documentation before it could run, and reviewed by
// reading first; the one bug that review found is recorded below.
//
// A coordinate, so a consuming build can substitute this project for it.
// Nothing publishes to it; it exists to be named. See
// tabular-center-kotlin/examples/06-generated/settings.gradle.kts.
plugins {
    kotlin("jvm") version "2.4.21"
}

val tabulaRepo: String? = System.getenv("TABULAR_CENTER_MAVEN_REPO")?.takeIf { it.isNotBlank() }

repositories {
    if (tabulaRepo != null) maven { url = uri(tabulaRepo) } else mavenCentral()
}

dependencies {
    implementation("com.google.devtools.ksp:symbol-processing-api:2.3.12")
}

sourceSets["main"].kotlin {
    srcDir("../codegen")
    exclude("Main.kt", "Tests.kt", "compile_fail/**", "golden/**", "support/**")
}

kotlin { jvmToolchain(21) }

apply(from = "../gradle/publication.gradle.kts")
