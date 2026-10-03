// Configures the four projects settings.gradle.kts names. Their directories
// are their source roots, so this file holds what a build file beside the
// sources would.
import org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension

plugins {
    kotlin("jvm") version "2.1.20" apply false
}

val tabulaRepo: String? = System.getenv("TABULAR_CENTER_MAVEN_REPO")?.takeIf { it.isNotBlank() }

subprojects {
    // Build output OUTSIDE the project directory, which is the source root:
    // a build/ inside it puts compileKotlin's and processResources' outputs in
    // the tree sourcesJar reads, and Gradle refuses the build ("implicit
    // dependency") however the files are excluded -- rightly, since the
    // sources jar must hold sources and nothing a build wrote.
    layout.buildDirectory.set(rootDir.resolve("build/${project.name}"))

    apply(plugin = "org.jetbrains.kotlin.jvm")

    repositories {
        if (tabulaRepo != null) maven { url = uri(tabulaRepo) } else mavenCentral()
    }

    configure<KotlinJvmProjectExtension> {
        jvmToolchain(21)
        // The project directory is the source root, packages and all, so the
        // sources jar keeps `center/tabula/Step.kt` paths IDEs attach by.
        sourceSets.getByName("main").kotlin {
            setSrcDirs(listOf(projectDir))
            // Nothing is built here any more; this only keeps a stale build/
            // from an older checkout out of the sources jar.
            exclude("build/**")
        }
    }

    apply(from = rootDir.resolve("gradle/publication.gradle.kts"))
}

project(":tabular-center-codegen") {
    configure<KotlinJvmProjectExtension> {
        // As ksp/build.gradle.kts compiles it: the emitter and its model, not
        // the kotlinc-only harness, fixtures or goldens beside them.
        sourceSets.getByName("main").kotlin {
            exclude("Main.kt", "Tests.kt", "compile_fail/**", "golden/**", "support/**")
        }
    }
}

project(":tabular-center-testing") {
    dependencies {
        // `api`: the testing harness's own signatures take core's types, so a
        // consumer compiling against it needs core too -- compile scope in
        // the POM, where `implementation` would publish runtime.
        "api"(project(":tabular-center-core"))
    }
}
