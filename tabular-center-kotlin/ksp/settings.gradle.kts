// The processor's own settings.
//
// `tabular-center-kotlin/ksp/README.md` recorded its absence as something to know before the
// first run: "Gradle will synthesise one for a standalone build and take the
// project name from the directory, which is `ksp`. Harmless for a build, wrong
// for publication."
//
// It stopped being harmless with the offline repository. An included build
// resolves its own plugins through its OWN pluginManagement, and a synthesised
// settings file defaults to the plugin portal -- so `kotlin("jvm")` here would
// still reach for the network however the example were configured. The example
// would resolve everything, hand off to the processor, and fail there, on a
// line naming a plugin rather than a repository.
//
// Naming the project also fixes the publication half, which is the smaller
// reason to have written this file and the one that would have gone on being
// deferred.
rootProject.name = "tabula-ksp"

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
