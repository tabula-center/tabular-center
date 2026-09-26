// The Compose Desktop example. See settings.gradle.kts for where artifacts
// come from -- the same offline switch `06-generated` uses.
//
// The first build file here with heavyweight third-party dependencies: Compose
// Multiplatform pulls in hundreds of artifacts, so `tabular-center-kotlin/nix/gradle-lock.json` has
// to carry them before this builds offline. `tabular-center-kotlin/tools/gradle-lock` regenerates
// it, with a network, on a developer machine.
plugins {
    kotlin("jvm") version "2.1.20"
    // The Compose compiler moved into the Kotlin distribution with 2.0, so
    // this version tracks the Kotlin one exactly, not the Compose one below.
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.20"
    // Compose Multiplatform: the runtime, the UI toolkit and the desktop
    // application plumbing.
    id("org.jetbrains.compose") version "1.8.0"
    id("com.google.devtools.ksp") version "2.1.20-1.0.32"
}

val tabulaRepo: String? = System.getenv("TABULAR_CENTER_MAVEN_REPO")?.takeIf { it.isNotBlank() }

repositories {
    if (tabulaRepo != null) {
        maven { url = uri(tabulaRepo) }
    } else {
        mavenCentral()
        // Compose Desktop's UI depends on androidx.lifecycle and
        // androidx.annotation, which are published to Google's repository and
        // to no other. Without this, resolution fails on artifacts whose names
        // do not mention Compose at all.
        google()
        maven { url = uri("https://maven.pkg.jetbrains.space/public/p/compose/dev") }
    }
}

// tabula from source, as every other example does.
sourceSets["main"].kotlin.srcDir("src")
sourceSets["main"].kotlin.srcDir("../../core")
sourceSets["main"].kotlin.srcDir("../../annotations")
sourceSets["test"].kotlin.srcDir("test")
sourceSets["test"].kotlin.srcDir("../harness")

dependencies {
    ksp("dev.tabula:tabula-ksp:0.1.0")

    // The state machine layer needs the Compose RUNTIME only -- `remember`,
    // `mutableStateOf`, recomposition. That is the point of the architecture:
    // a machine is testable without a toolkit. The UI layer is what needs
    // Compose UI.
    implementation(compose.runtime)
    implementation(compose.desktop.currentOs)

    testImplementation(compose.runtime)
}

kotlin { jvmToolchain(21) }

compose.desktop {
    application {
        mainClass = "example.compose.MainKt"
    }
}

// The checks are `main` functions, as in every other Kotlin example: the
// shared four-function harness, not JUnit. `gradle build` compiles them and
// runs nothing, so run them.
val runChecks by tasks.registering(JavaExec::class) {
    dependsOn(tasks.named("testClasses"))
    classpath = sourceSets["test"].runtimeClasspath
    // Root package: the checks sit there so they can call `Check`, which has
    // no package and therefore cannot be imported into one.
    mainClass.set("MachineCheckKt")
}

tasks.named("check") { dependsOn(runChecks) }
