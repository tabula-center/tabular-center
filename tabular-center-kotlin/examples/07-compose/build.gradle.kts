// The Compose Desktop example. See settings.gradle.kts for where artifacts
// come from -- the same offline switch `06-generated` uses.
//
// The first build file here with heavyweight third-party dependencies: Compose
// Multiplatform pulls in hundreds of artifacts, so `tabular-center-kotlin/nix/gradle-lock.json` has
// to carry them before this builds offline. `tabular-center-kotlin/tools/gradle-lock` regenerates
// it, with a network, on a developer machine.
//
// The Compose compiler moved into the Kotlin distribution with 2.0, so
// this version tracks the Kotlin one exactly, not the Compose one below.
plugins {
    kotlin("jvm") version "2.4.21"
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.21"
    id("org.jetbrains.compose") version "1.12.1"
    id("com.google.devtools.ksp") version "2.3.12"
}

val tabulaRepo: String? = System.getenv("TABULAR_CENTER_MAVEN_REPO")?.takeIf { it.isNotBlank() }

repositories {
    if (tabulaRepo != null) {
        maven { url = uri(tabulaRepo) }
    } else {
        mavenCentral()
        google()
        maven { url = uri("https://maven.pkg.jetbrains.space/public/p/compose/dev") }
    }
}

val desktopTarget: String? = providers.gradleProperty("desktopTarget").orNull

val resolveForLock by tasks.registering {
    val classpath = configurations.named("testRuntimeClasspath")
    doLast { classpath.get().resolve() }
}

sourceSets["main"].kotlin.srcDir("src")
sourceSets["main"].kotlin.srcDir("../../core")
sourceSets["main"].kotlin.srcDir("../../annotations")
sourceSets["test"].kotlin.srcDir("test")
sourceSets["test"].kotlin.srcDir("../harness")

dependencies {
    ksp("center.tabula:tabular-center-ksp:0.1.0")

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

val runChecks by tasks.registering(JavaExec::class) {
    dependsOn(tasks.named("testClasses"))
    classpath = sourceSets["test"].runtimeClasspath
    mainClass.set("MachineCheckKt")
}

tasks.named("check") { dependsOn(runChecks) }
