/**
 * The hand-written half of a generated machine: the sealed hierarchies and the
 * context. A developer writes these; `codegen/golden/timer.kt.golden` is what
 * the generator adds.
 *
 * Kept separate so the emitted source can be compiled on its own, which is the
 * point of the `kotlin-codegen` verify step.
 */
package generated.timer

sealed interface S {
    data object Idle : S
    data class Running(val since: Long) : S
    data object Done : S
}

sealed interface A {
    data object Start : A
    data class Tick(val now: Long) : A
    data object Cancel : A
}

sealed interface F {
    data object StartClock : F
    data object StopClock : F
}

class Ctx(val limit: Long)
