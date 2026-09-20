//~ EXPECT: can only be called from a coroutine or another suspend function
//
// COLOR FLOWS ONE WAY.
//
// `generated.jobmixed` is plain and delegates to `retrysuspend`, whose `step`
// is `suspend`. The generated `delegateToRetrysuspend` carries the PARENT's
// color, so it is a plain function calling a suspend one -- and kotlinc
// refuses it. By construction: tabula emits no diagnostic of its own, and
// there is nothing to circumvent. The reverse direction is
// support/CompleteJobSuspend.kt, which must compile.
//
// The expected text is kotlinc 2.x's (K2): "can only be called from a
// coroutine". K1 said "should be called only from", which is what this line
// first guessed and why it failed once.
//
// The error is in the emitted `refused/jobmixed.kt`, which tools/verify
// compiles with this file because the check marks the machine refused. This
// file supplies only the parent's hand-written types.
package generated.jobmixed

sealed interface S {
    data object Idle : S
    data class Retrying(val child: generated.retrysuspend.S) : S
    data object Done : S
}

sealed interface A {
    data object Run : A
    data object Tick : A
    data object Cancel : A
}

sealed interface F {
    data object Log : F
}

class Ctx(val retry: generated.retrysuspend.Ctx)
