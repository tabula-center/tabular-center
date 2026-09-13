/**
 * **6. A machine whose dispatcher is generated, not written.**
 *
 * Every other Kotlin example hand-writes its `step`, because there is no
 * annotation processor in this environment to write one. This one does not:
 * its dispatcher is produced at build time by the same emitter the KSP
 * processor calls, from the same `MachineDesc` the processor builds.
 *
 * It is the only example that needs Gradle, because KSP is a Maven artifact.
 * Where Gradle is absent it is **skipped**, not failed and not faked: there is
 * no `Cells` interface for `Impl.kt` to implement until the processor has run,
 * and standing in for it with a hand-written `MachineDesc` would be committing
 * by hand exactly what this example exists to generate.
 *
 * The types a developer writes. The dispatcher, the `Cells` interface and the
 * effect-handler surface are generated from these plus the rows in `gen/`.
 */
package generated.turnstile

sealed interface S {
    data object Locked : S
    data object Unlocked : S
}

sealed interface A {
    data object Coin : A
    data object Push : A
}

sealed interface F {
    data object Click : F
}

class Ctx {
    var admitted = 0
}
