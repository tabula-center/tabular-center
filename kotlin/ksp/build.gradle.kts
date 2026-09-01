// UNVERIFIED. Written from the KSP documentation, never run -- Gradle needs
// Maven Central and this environment cannot reach it. See README.md.
plugins {
    kotlin("jvm") version "2.1.20"
}

repositories { mavenCentral() }

dependencies {
    implementation("com.google.devtools.ksp:symbol-processing-api:2.1.20-1.0.32")
    // The generator's logic lives in ../codegen and is tested with kotlinc
    // alone; this module is only the KSP adapter over it.
    implementation(files("../codegen"))
}

kotlin { jvmToolchain(21) }
