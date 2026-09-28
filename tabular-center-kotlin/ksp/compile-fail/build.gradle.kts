// One fixture at a time, named by `-PtabulaFixture=<file>`.
//
// Per-fixture rather than all at once, and the cost is a Gradle invocation
// each. The reason is isolation: KSP reports what it finds in a round, and a
// fixture whose machine is malformed enough to stop the processor early would
// swallow the diagnostics of every fixture compiled beside it. A harness that
// silently checks fewer things than it claims is the failure this repository
// has now found in five different places.
plugins {
    kotlin("jvm") version "2.1.20"
    id("com.google.devtools.ksp") version "2.1.20-1.0.32"
}

val tabulaRepo: String? = System.getenv("TABULAR_CENTER_MAVEN_REPO")?.takeIf { it.isNotBlank() }

repositories {
    if (tabulaRepo != null) maven { url = uri(tabulaRepo) } else mavenCentral()
}

// The fixture under test, and nothing else. `fixtures/` as a whole is never a
// source set: every file in it is expected to fail, so compiling them together
// would be one build failing for eight reasons.
val fixture: String = (findProperty("tabulaFixture") as String?)
    ?: error(
        "tabular-center: no fixture selected. This build compiles ONE compile-fail " +
            "fixture and expects it to fail; run it through " +
            "`tools/verify kotlin-ksp-compile-fail` rather than directly."
    )

sourceSets["main"].kotlin.setSrcDirs(
    listOf(
        "fixtures/$fixture",
        "../../core",
        "../../annotations",
    )
)

dependencies {
    ksp("dev.tabularcenter:tabular-center-ksp:0.1.0")
}

kotlin { jvmToolchain(21) }
