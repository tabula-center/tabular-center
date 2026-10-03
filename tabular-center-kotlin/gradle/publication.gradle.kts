// How every Kotlin artifact is published to Maven Central. Applied by the
// four projects of this directory's build and by ksp/build.gradle.kts, so the
// coordinates, the POM and the signing are written once.
//
// Only Gradle's own plugins (maven-publish, signing): a third-party publishing
// plugin would add to the artifact set nix pins (nix/gradle-lock.json), which
// only `nix run .#gradle-lock`, with network, can regenerate.
//
// Inert in an ordinary build. It publishes only to a staging directory
// tools/central-bundle names (TABULAR_CENTER_STAGING), and signs only when a
// key is given (SIGNING_KEY) -- so the example builds that include ksp/ see
// nothing but two extra jar tasks.
import org.gradle.api.publish.PublishingExtension
import org.gradle.api.publish.maven.MavenPublication
import org.gradle.plugins.signing.SigningExtension

apply(plugin = "maven-publish")
apply(plugin = "signing")

// One VERSION for all three languages (RELEASING.md), found by walking up:
// this file serves builds rooted at tabular-center-kotlin/ and at ksp/.
fun releaseVersion(): String {
    var dir: File? = projectDir
    while (dir != null) {
        val f = File(dir, "VERSION")
        if (f.isFile) return f.readText().trim()
        dir = dir.parentFile
    }
    error("no VERSION file above $projectDir")
}

group = "center.tabula"
version = releaseVersion()

val descriptions = mapOf(
    "tabular-center-core" to "Transition-matrix state machines: Step, Cell, Table, drivers, export and lints.",
    "tabular-center-annotations" to "The @Machine, @Row and @Path annotations a tabular-center matrix is declared with.",
    "tabular-center-codegen" to "The tabular-center code generator: a machine description in, Kotlin source out.",
    "tabular-center-ksp" to "The KSP processor that turns a tabular-center matrix into its generated surface.",
    "tabular-center-testing" to "The .tbl fixture harness for testing tabular-center machines.",
)

// Central requires a sources jar and a javadoc jar beside every jar. The
// sources are Kotlin, so the javadoc jar is empty, which Central accepts.
configure<JavaPluginExtension> {
    withSourcesJar()
    withJavadocJar()
}

configure<PublishingExtension> {
    publications {
        create<MavenPublication>("maven") {
            from(components["java"])
            artifactId = project.name
            pom {
                name.set(project.name)
                description.set(descriptions[project.name] ?: error("no description for ${project.name}"))
                url.set("https://tabula.center")
                licenses {
                    license {
                        name.set("MIT")
                        url.set("https://opensource.org/license/mit")
                        distribution.set("repo")
                    }
                }
                developers {
                    developer {
                        id.set("hadilq")
                        name.set("hadilq")
                        url.set("https://github.com/hadilq")
                    }
                }
                scm {
                    url.set("https://github.com/tabula-center/tabular-center")
                    connection.set("scm:git:https://github.com/tabula-center/tabular-center.git")
                    developerConnection.set("scm:git:ssh://git@github.com/tabula-center/tabular-center.git")
                }
            }
        }
    }
    repositories {
        val staging: String? = System.getenv("TABULAR_CENTER_STAGING")?.takeIf { it.isNotBlank() }
        if (staging != null) {
            maven {
                name = "staging"
                url = uri(staging)
            }
        }
    }
}

fun gradleKeyId(given: String): String {
    val hex = given.trim().removePrefix("0x").removePrefix("0X").replace(" ", "")
    require(hex.length in setOf(8, 16, 40) && hex.all { it.isDigit() || it.uppercaseChar() in 'A'..'F' }) {
        "SIGNING_KEY_ID must be the signing subkey's ID or fingerprint in hex: 8, 16 or 40 " +
            "digits, 0x optional (given: '$given'). See `gpg --list-secret-keys --keyid-format long`, " +
            "the ssb line marked [S]."
    }
    return hex.takeLast(8).uppercase()
}

val signingKey: String? = System.getenv("SIGNING_KEY")?.takeIf { it.isNotBlank() }
if (signingKey != null) {
    val signingKeyId = System.getenv("SIGNING_KEY_ID")?.takeIf { it.isNotBlank() }?.let { gradleKeyId(it) }
        ?: error(
            "SIGNING_KEY is set but SIGNING_KEY_ID is not: name the signing subkey, the ssb line " +
                "marked [S] in `gpg --list-secret-keys --keyid-format long`"
        )
    configure<SigningExtension> {
        useInMemoryPgpKeys(signingKeyId, signingKey, System.getenv("SIGNING_KEY_PASSWORD") ?: "")
        sign(the<PublishingExtension>().publications)
    }
}
