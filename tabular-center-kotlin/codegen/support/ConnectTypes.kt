/**
 * The types of the `connect` machine, which exists to exercise the narrowed
 * surface: see `Main.kt` and spec/happy-paths.md.
 */
package generated.connect

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

sealed interface F {
    data object Banner : F
}

class Ctx
