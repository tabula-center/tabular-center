// The types `SessionMachine.tb.kt` refers to.
package example.compose.session

sealed interface S {
    data object Booting : S

    /** The parent's state CONTAINS the child's. That is what composition is. */
    data class Running(val child: example.compose.connection.S) : S

    data object Ended : S
}

sealed interface A {
    data object Boot : A

    /** One action for the whole nested screen: the prism decides what it means. */
    data object Tap : A

    data object Finish : A
}

sealed interface F {
    data object Note : F
}

/** Contains the child's context, so `connectionChildCtx` is a field access. */
class Ctx(val connection: example.compose.connection.Ctx)
