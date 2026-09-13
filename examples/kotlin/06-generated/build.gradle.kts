// UNVERIFIED. See settings.gradle.kts.
//
// This is the only build file in the repository that runs the annotation
// processor, and it exists so the examples cover the path a user actually
// takes: annotations in, dispatcher out, nothing generated committed.
plugins {
    kotlin("jvm") version "2.1.20"
    // KSP releases are tied to a specific Kotlin compiler build, so this
    // version and the one above move together or not at all.
    id("com.google.devtools.ksp") version "2.1.20-1.0.32"
}

repositories { mavenCentral() }

// tabula is not published to any repository yet, so the runtime and the
// annotations are compiled from source. `srcDir` and not `files()`: those
// directories hold .kt sources, and `files()` would put them on the classpath
// as directories of class files and resolve nothing.
// The example's own sources live in `src/`, not Gradle's default
// `src/main/kotlin`. Saying so is not optional: without it the default source
// set does not exist, Gradle compiles nothing from this directory, and the
// build succeeds having produced no dispatcher at all -- a green build for an
// example that demonstrated nothing.
sourceSets["main"].kotlin.srcDir("src")

sourceSets["main"].kotlin.srcDir("../../../kotlin/core")
sourceSets["main"].kotlin.srcDir("../../../kotlin/annotations")

// Same for the checks, which are in `test/`. They are a separate compilation
// unit compiled against the generated dispatcher, which is the property the
// Kotlin examples were restructured for.
sourceSets["test"].kotlin.srcDir("test")

dependencies {
    ksp(project(":processor"))
}

kotlin { jvmToolchain(21) }

// The generated sources land in build/generated/ksp/ and are compiled from
// there. Nothing in that tree is committed, which is the point: `Impl.kt`
// implements an interface that does not exist until this runs, so a stale
// commit of it would be the one kind of drift the compiler could not catch.
