// The types `Spine.tb.kt` refers to. Ordinary Kotlin, formatted normally.
package generated.spine

sealed interface S {
    data object Idle : S
    data object Connecting : S
    data object Live : S
    data object Failed : S
}

sealed interface A {
    data object Start : A
    data object Ready : A
    data object Drop : A
}

sealed interface F

class Ctx
