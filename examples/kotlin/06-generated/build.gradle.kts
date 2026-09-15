// The KSP example. See settings.gradle.kts for where artifacts come from.
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

// Same switch as pluginManagement in settings.gradle.kts, and it has to be
// made twice: plugin resolution and dependency resolution read different
// repository lists, and an offline build that finds its plugins and not its
// dependencies fails halfway through with a message about neither.
val tabulaRepo: String? = System.getenv("TABULA_MAVEN_REPO")?.takeIf { it.isNotBlank() }

repositories {
    if (tabulaRepo != null) maven { url = uri(tabulaRepo) } else mavenCentral()
}

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

// The shared assertion harness. Every other Kotlin example gets it because
// tools/verify compiles harness/Check.kt and puts it on the classpath by hand;
// this one is built by Gradle, and nothing told Gradle it existed:
//
//   e: test/GeneratedTest.kt:21:5 Unresolved reference 'Check'.
//
// Found the first time a real `gradle build` ran. Worth noting that the Nix
// derivation could never have found it -- it stops at dependency resolution,
// so a missing source set is invisible to it.
sourceSets["test"].kotlin.srcDir("../harness")

dependencies {
    // Named, and substituted to the included build in settings.gradle.kts.
    ksp("dev.tabula:tabula-ksp:0.1.0")
}

kotlin { jvmToolchain(21) }

// The generated sources land in build/generated/ksp/ and are compiled from
// there. Nothing in that tree is committed, which is the point: `Impl.kt`
// implements an interface that does not exist until this runs, so a stale
// commit of it would be the one kind of drift the compiler could not catch.
