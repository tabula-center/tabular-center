// The types `Spec.tb.kt` refers to. Ordinary Kotlin, formatted normally; the
// matrix lives in the `.tb.kt` beside it (`spec/matrix-files.md`).
package fixtures.unknowneffect

import dev.tabula.Step

sealed interface S {
    data object Idle : S
    data object Busy : S
}

sealed interface A {
    data object Start : A
    data object Stop : A
}

sealed interface F {
    data object Beep : F

    /** A real effect the `effects` list does not mention. */
    data object Whirr : F
}

class Ctx
