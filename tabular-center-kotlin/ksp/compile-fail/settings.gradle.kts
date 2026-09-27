// The KSP compile-fail harness.
//
// Its own Gradle build rather than a source set of the example, because the
// whole point is that it FAILS to compile, and a build that must fail cannot
// share an invocation with one that must succeed.
//
// Nothing new is resolved here: the same two plugins and the same processor
// the example already uses, so tabular-center-kotlin/nix/gradle-lock.json covers this build without
// being regenerated. That was the constraint worth designing around --
// KSP compile-testing as a library would have meant a new dependency, a
// re-lock, and an embedded Kotlin compiler in the offline artifact set.
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

rootProject.name = "tabular-center-ksp-compile-fail"

includeBuild("..") {
    dependencySubstitution {
        substitute(module("dev.tabularcenter:tabular-center-ksp"))
            .using(project(":"))
            .because("the harness builds the processor from source, not from a repository")
    }
}
