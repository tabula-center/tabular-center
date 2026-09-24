// The types `Machine.tb.kt` refers to. Ordinary Kotlin, formatted normally.
package example.compose.connection

sealed interface S {
    data object Idle : S

    data object Connecting : S

    /** Payload: what the UI shows, carried by the state rather than beside it. */
    data class Live(val since: Int) : S

    data object Failed : S
}

sealed interface A {
    data object Start : A

    data class Ready(val at: Int) : A

    data object Drop : A

    data object Retry : A
}

sealed interface F {
    data object Dial : F
    data object Hangup : F
}

/** What the cells are given. A clock here; a socket in a real one. */
class Ctx(val now: () -> Int)
