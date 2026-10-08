// Configures the four projects settings.gradle.kts names. Their directories
// are their source roots, so this file holds what a build file beside the
// sources would.
import org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension

plugins {
    kotlin("jvm") version "2.4.21" apply false
}

val tabulaRepo: String? = System.getenv("TABULAR_CENTER_MAVEN_REPO")?.takeIf { it.isNotBlank() }

subprojects {
    layout.buildDirectory.set(rootDir.resolve("build/${project.name}"))

    apply(plugin = "org.jetbrains.kotlin.jvm")

    repositories {
        if (tabulaRepo != null) maven { url = uri(tabulaRepo) } else mavenCentral()
    }

    configure<KotlinJvmProjectExtension> {
        jvmToolchain(21)
        sourceSets.getByName("main").kotlin {
            setSrcDirs(listOf(projectDir))
            exclude("build/**")
        }
    }

    apply(from = rootDir.resolve("gradle/publication.gradle.kts"))
}

project(":tabular-center-codegen") {
    configure<KotlinJvmProjectExtension> {
        sourceSets.getByName("main").kotlin {
            exclude("Main.kt", "Tests.kt", "compile_fail/**", "golden/**", "support/**")
        }
    }
}

project(":tabular-center-testing") {
    dependencies {
        "api"(project(":tabular-center-core"))
    }
}
