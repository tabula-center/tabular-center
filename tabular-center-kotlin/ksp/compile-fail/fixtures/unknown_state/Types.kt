// The types `Spec.tb.kt` refers to. Ordinary Kotlin, formatted normally; the
// matrix lives in the `.tb.kt` beside it (`spec/matrix-files.md`).
package fixtures.unknownstate

import dev.tabula.Step

sealed interface S {
    data object Idle : S
    data object Busy : S

    /**
     * A real type that the `states` list does not mention.
     *
     * That is the whole fixture: `GO` names it, `S` declares it, and the
     * machine does not. Without the check the emitter would render
     * `S.Parked` into a `when` arm that compiles, and the table would claim a
     * state the machine has no row for.
     */
    data object Parked : S
}

sealed interface A {
    data object Start : A
    data object Stop : A
}

sealed interface F

class Ctx
