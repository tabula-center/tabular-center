/**
 * The same parent as JobTypes.kt, generated `suspend` over the plain child. Its
 * `Retrying` state holds the child's state, and its context contains the
 * child's, so `retryChildCtx` is a field access.
 */
package generated.jobsuspend

sealed interface S {
    data object Idle : S
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

class Ctx(val retry: generated.retry.Ctx)
