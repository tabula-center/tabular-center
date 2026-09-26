// The types `Retry.tb.kt` refers to. Ordinary Kotlin, formatted normally; the
// matrix lives in the `.tb.kt` beside it (`spec/matrix-files.md`).
package generated.retry

sealed interface S {
    data object Ready : S

    data class Waiting(val attempt: Int) : S

    data object Exhausted : S
}

sealed interface A {
    data object Attempt : A
    data object Elapsed : A
    data object Abort : A
}

sealed interface F {
    data object Sleep : F
    data object GiveUp : F
}

/** How many attempts the child is allowed. The parent's context contains it. */
class Ctx(val maxAttempts: Int)
