// The published Kotlin artifacts, as one Gradle build: the four that compile
// from their own directories. The KSP processor is a build of its own
// (ksp/), because three example builds include it to substitute
// `center.tabula:tabular-center-ksp`; it applies the same
// gradle/publication.gradle.kts, and tools/central-bundle stages both into
// one Maven Central bundle. RELEASING.md, "The artifacts".
//
// Each project's directory is its source directory, packages and all, so no
// build file sits among the sources: build.gradle.kts here configures them.
//
// Offline under nix (the pinned set gradle-lock.json describes), the
// public repositories otherwise -- as ksp/settings.gradle.kts does.
rootProject.name = "tabular-center-kotlin"

include(
    ":tabular-center-core",
    ":tabular-center-annotations",
    ":tabular-center-codegen",
    ":tabular-center-testing",
)
project(":tabular-center-core").projectDir = file("core")
project(":tabular-center-annotations").projectDir = file("annotations")
project(":tabular-center-codegen").projectDir = file("codegen")
project(":tabular-center-testing").projectDir = file("testing")

pluginManagement {
    val tabulaRepo: String? = System.getenv("TABULAR_CENTER_MAVEN_REPO")?.takeIf { it.isNotBlank() }
    repositories {
        if (tabulaRepo != null) {
            maven { url = uri(tabulaRepo) }
        } else {
            gradlePluginPortal()
            mavenCentral()
        }
    }
}
