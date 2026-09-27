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

// Compose Desktop's artifact is per OS and CPU: `compose.desktop.currentOs`
// is `desktop-jvm-linux-x64` on one machine and `desktop-jvm-macos-arm64` on
// the next, each with native libraries of its own. The lock is generated on
// one machine, so it held only that machine's -- and the macOS CI job failed
// looking for an artifact the lock had never heard of.
//
// `-PdesktopTarget=macos-arm64` (or any key of `desktopTargets` in the
// dependencies block) swaps in another platform's artifact.
// tabular-center-kotlin/tools/gradle-lock passes each in turn to
// `resolveForLock` below, so the lock carries every platform nix builds on.
// Nothing else sets it; a normal build gets `currentOs`.
//
// Only the property is read here. The platform names are read INSIDE
// `dependencies {}`, because that is the only place `compose` means the
// dependency accessors: at the top level of this script `compose` is the
// plugin's extension -- the thing `compose.desktop { application {} }`
// configures -- and its `desktop` has no `currentOs`, no `macos_arm64`.
val desktopTarget: String? = providers.gradleProperty("desktopTarget").orNull

// Downloads everything the checks need at runtime, and does nothing else:
// `build` would also compile and run a machine against another platform's
// natives. Resolution goes through the real classpath, so the platform
// variants are chosen by the same rules as in a normal build.
val resolveForLock by tasks.registering {
    val classpath = configurations.named("testRuntimeClasspath")
    doLast { classpath.get().resolve() }
}

// tabular-center from source, as every other example does.
sourceSets["main"].kotlin.srcDir("src")
sourceSets["main"].kotlin.srcDir("../../core")
sourceSets["main"].kotlin.srcDir("../../annotations")
sourceSets["test"].kotlin.srcDir("test")
sourceSets["test"].kotlin.srcDir("../harness")

dependencies {
    ksp("dev.tabularcenter:tabular-center-ksp:0.1.0")

    // The state machine layer needs the Compose RUNTIME only -- `remember`,
    // `mutableStateOf`, recomposition. That is the point of the architecture:
    // a machine is testable without a toolkit. The UI layer is what needs
    // Compose UI.
    implementation(compose.runtime)

    val desktopTargets: Map<String, String> = mapOf(
        "linux-x64" to compose.desktop.linux_x64,
        "linux-arm64" to compose.desktop.linux_arm64,
        "macos-x64" to compose.desktop.macos_x64,
        "macos-arm64" to compose.desktop.macos_arm64,
    )
    implementation(
        desktopTarget?.let { desktopTargets[it] ?: error("desktopTarget=$it; known: ${desktopTargets.keys}") }
            ?: compose.desktop.currentOs,
    )

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
