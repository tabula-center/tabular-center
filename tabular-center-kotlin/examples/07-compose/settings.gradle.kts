// The KSP example's settings. This build has run: see tabular-center-kotlin/ksp/README.md,
// where the missing `../harness` source set was found by running it.
// Where plugins come from, declared rather than defaulted.
//
// Gradle's default is the plugin portal alone, and the first build in the Nix
// sandbox failed there:
//
//   Plugin [id: 'org.jetbrains.kotlin.jvm', version: '2.1.20'] was not found
//   Searched in the following repositories:
//     Gradle Central Plugin Repository
//
// mavenCentral() is added because both the Kotlin and KSP plugins publish
// their marker artifacts there too, so resolution has a second source that is
// the same one the dependencies already come from.
//
// TABULAR_CENTER_MAVEN_REPO switches the whole set for one offline directory. An
// environment variable, not a Gradle property: `-P` does not cross into an
// included build, and `tabular-center-kotlin/ksp` is one -- so a property would configure
// this build and leave the processor still reaching for the network, which
// fails later, elsewhere, and reads like a different problem.
//
// Set: tabular-center-kotlin/nix/gradle-repo.nix built it from tabular-center-kotlin/nix/gradle-lock.json and `nix flake
// check` points here at the store path. Unset: the online repositories, which
// is what tabular-center-kotlin/tools/gradle-lock and ci.yml's check-no-nix job use.
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

rootProject.name = "tabula-example-compose"

// The processor, as an included build substituted for its coordinate.
//
// This was `include(":processor")` with a projectDir, which makes the
// processor a subproject of the example -- so the example's build owns the
// processor's lifecycle, and `ksp(project(":processor"))` couples them by path
// rather than by name.
//
// A composite build is the right shape: the example depends on
// `dev.tabula:tabula-ksp` the way any consumer would, and the substitution
// says "resolve that from source, here". Nothing is published to that
// coordinate; it exists to be named, which is the point -- when the processor
// is published, deleting this block is the whole migration.
includeBuild("../../ksp") {
    dependencySubstitution {
        substitute(module("dev.tabula:tabula-ksp"))
            .using(project(":"))
            .because("the example builds the processor from source, not from a repository")
    }
}
