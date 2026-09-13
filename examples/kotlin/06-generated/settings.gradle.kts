// UNVERIFIED, for the same reason kotlin/ksp is: Gradle needs Maven Central
// and this environment cannot reach it.
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
pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

rootProject.name = "tabula-example-generated"

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
includeBuild("../../../kotlin/ksp") {
    dependencySubstitution {
        substitute(module("dev.tabula:tabula-ksp"))
            .using(project(":"))
            .because("the example builds the processor from source, not from a repository")
    }
}
