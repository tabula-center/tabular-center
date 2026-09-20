/**
 * The same child as RetryTypes.kt, generated `suspend`: the colored child.
 *
 * A root package named `retry` because a parent reaches its child through the
 * alias as a fully qualified name -- `retry.Cells`, `retry.step` -- so the
 * alias and the package are the same word. See `retryDesc` in Main.kt.
 */
package retrysuspend

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

class Ctx(val maxAttempts: Int)
