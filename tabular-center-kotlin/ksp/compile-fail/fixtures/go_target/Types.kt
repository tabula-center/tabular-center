// The types `Spec.tb.kt` refers to. Ordinary Kotlin, formatted normally; the
// matrix lives in the `.tb.kt` beside it (`spec/matrix-files.md`).
package fixtures.gotarget

import dev.tabula.Step

sealed interface S {
    data object Idle : S

    /**
     * Carries a payload, which is what makes the fixture work.
     *
     * A GO cell is resolved entirely by the generator, so its target has to be
     * constructible from the matrix alone. `Running` cannot be: nobody has
     * said what `since` should hold.
     */
    data class Running(val since: Long) : S
}

sealed interface A {
    data object Start : A
    data object Stop : A
}

sealed interface F

class Ctx
