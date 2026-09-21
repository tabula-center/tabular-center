// The types `Gate.tb.kt` refers to, plus the machine's context.
//
// A second machine in this example, and the first COLORED one anywhere in the
// examples. `Turnstile` next door is plain; this one's prototype is `suspend`,
// which is the library's headline claim demonstrated rather than described:
// the generator copies whatever modifiers the prototype carries instead of
// enumerating the ones it knows about.
package generated.gate

sealed interface S {
    data object Closed : S
    data object Opening : S
    data object Open : S
}

sealed interface A {
    data object Request : A
    data object Arrived : A
}

sealed interface F {
    /** Carries a payload, and a static cell emits it: see `Gate.tb.kt`. */
    data class Chime(val volume: Int) : F
}

/** Whatever a real gate would need. Empty here; the colour is the point. */
class Ctx
