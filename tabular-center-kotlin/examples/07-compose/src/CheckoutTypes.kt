// The types `CheckoutMachine.tb.kt` refers to.
package example.compose.checkout

sealed interface S {
    // The five states of the happy path. All payload-free, and that is not an
    // accident: a spine's derived `GO` carries no constructor arguments, so a
    // state on the path cannot need any. `tabula::go-target` says so if one
    // does -- which is the rule arriving before the mistake, not after it.
    data object Cart : S

    data object Address : S

    data object Payment : S

    data object Review : S

    data object Placed : S

    /** Off the path, and carrying why. Reached by a GO that supplies it. */
    data class Declined(val reason: String) : S

    data object Abandoned : S
}

sealed interface A {
    data object Next : A
    data object Back : A
    data object Decline : A
    data object Abandon : A
}

sealed interface F {
    // Payload-free, both of them: a static cell emits what is written where it
    // is written, and the amount is the context's, read when the effect runs.
    data object Charge : F

    data object Email : F
}

class Ctx(val total: Int)
