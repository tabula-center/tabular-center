// The KSP example. See settings.gradle.kts for where artifacts come from.
//
// This is the only build file in the repository that runs the annotation
// processor, and it exists so the examples cover the path a user actually
// takes: annotations in, dispatcher out, nothing generated committed.
//
// KSP releases are tied to a specific Kotlin compiler build, so this
// version and the one above move together or not at all.
plugins {
    kotlin("jvm") version "2.4.21"
    id("com.google.devtools.ksp") version "2.3.12"
}

val tabulaRepo: String? = System.getenv("TABULAR_CENTER_MAVEN_REPO")?.takeIf { it.isNotBlank() }

repositories {
    if (tabulaRepo != null) maven { url = uri(tabulaRepo) } else mavenCentral()
}

sourceSets["main"].kotlin.srcDir("src")

sourceSets["main"].kotlin.srcDir("../../core")
sourceSets["main"].kotlin.srcDir("../../annotations")

sourceSets["test"].kotlin.srcDir("test")

sourceSets["test"].kotlin.srcDir("../harness")

dependencies {
    ksp("center.tabula:tabular-center-ksp:0.1.0")
}

kotlin { jvmToolchain(21) }

val exampleChecks = listOf("GeneratedTestKt", "GateTestKt", "StopwatchTestKt").map { mainClassName ->
    tasks.register<JavaExec>("run$mainClassName") {
        group = "verification"
        description = "Runs the $mainClassName checks against the generated dispatcher."
        classpath = sourceSets["test"].runtimeClasspath
        mainClass.set(mainClassName)
    }
}
tasks.named("check") { dependsOn(exampleChecks) }

tasks.named<Test>("test") { enabled = false }
