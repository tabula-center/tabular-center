/**
 * **6. A machine whose dispatcher is generated, not written.**
 *
 * Every other Kotlin example hand-writes its `step`. This one does not: the
 * KSP processor reads the annotations in `Machine.tb.kt` and writes the
 * dispatcher at build time, into `build/generated/ksp/`.
 *
 * It is the only example that needs Gradle, because KSP is a Maven artifact.
 * `nix flake check` builds it offline against `tabular-center-kotlin/nix/gradle-lock.json`; without
 * nix and without network it is **skipped**, not faked: there is no `Cells`
 * interface for `Impl.kt` to implement until the processor has run.
 *
 * The types a developer writes. The dispatcher, the `Cells` interface and the
 * effect-handler surface are generated from these plus the rows in
 * `Machine.tb.kt`.
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
