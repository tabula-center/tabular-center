/**
 * The Timer's hand-written types again, in the rendering twin's package.
 *
 * `timerrender` is `timerDesc` plus a rendering prototype, emitted into its
 * own package so the two can be compiled side by side; the types are the
 * Timer's, unchanged, because the rendering surface adds members and adds no
 * types. Compiled beside the emitted source by `tools/verify kotlin-codegen`.
 */
package generated.timerrender

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

    /** Payload-carrying, and emitted by a static cell. */
    data class Halt(val reason: String) : F
}

class Ctx(val limit: Long)
