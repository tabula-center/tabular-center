// The types the fixture's matrix refers to. Ordinary Kotlin; the matrix is in
// `ComposableSpec.tb.kt`.
package fixtures.composabletransition

sealed interface S {
    data object Idle : S
    data object Busy : S
}

sealed interface A {
    data object Start : A
    data object Stop : A
}

sealed interface F

class Ctx
