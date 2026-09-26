/**
 * The hand-written half of the generated Retry machine: the child.
 *
 * An ordinary nested package. The parent reaches it through
 * `ChildDesc.packageName` -- `generated.retry.Cells`, `generated.retry.step`
 * -- and names its members through the alias, `retry`.
 */
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

class Ctx(val maxAttempts: Int)
