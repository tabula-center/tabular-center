// The types `Job.tb.kt` refers to. Ordinary Kotlin, formatted normally; the
// matrix lives in the `.tb.kt` beside it (`spec/matrix-files.md`).
package generated.job

sealed interface S {
    data object Idle : S

    /** Holds the child's state: the parent's state contains the child's. */
    data class Retrying(val child: generated.retry.S) : S

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

/** Contains the child's context, so `retryChildCtx` is a field access. */
class Ctx(val retry: generated.retry.Ctx)
