package generated.toggle

sealed interface S {
    data object Off : S
    data object On : S
}

sealed interface A {
    data object Flip : A
    data object Poke : A
    data object Reset : A
}

sealed interface F {
    data object Light : F
    data object Buzz : F
}

class Ctx
