// UNVERIFIED, for the same reason kotlin/ksp is: Gradle needs Maven Central
// and this environment cannot reach it.
rootProject.name = "tabula-example-generated"

// The processor, by path. It is not published anywhere, and an example should
// depend on it the way the repository has it rather than the way a future
// release might.
include(":processor")
project(":processor").projectDir = file("../../../kotlin/ksp")
