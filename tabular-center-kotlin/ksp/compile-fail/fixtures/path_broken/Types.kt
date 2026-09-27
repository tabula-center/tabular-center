// The types `Spec.tb.kt` refers to. Ordinary Kotlin, formatted normally; the
// matrix lives in the `.tb.kt` beside it (`spec/matrix-files.md`).
package fixtures.pathbroken

import dev.tabularcenter.Step

sealed interface S {
    data object Idle : S
    data object Busy : S
    data object Done : S
}

sealed interface A {
    data object Start : A
    data object Stop : A
}

sealed interface F

class Ctx
