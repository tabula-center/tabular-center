// The types the fixture's matrix refers to. Ordinary Kotlin; the matrix is in
// `CollisionSpec.tb.kt`.
package fixtures.membercollision

sealed interface S {
    data object LogIn : S
    data object Log : S
}

sealed interface A {
    data object Start : A
    data object InStart : A
}

sealed interface F

class Ctx
