/**
 * The same child as RetryTypes.kt, generated `suspend`: the colored child.
 *
 * Reached by `generated.jobmixed` through `ChildDesc.packageName`, as
 * `generated.retrysuspend.step` -- a `suspend` call from a plain helper, which
 * is what that fixture exists to have refused.
 */
package generated.retrysuspend

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
