// The types `Spec.tb.kt` refers to. Ordinary Kotlin, formatted normally; the
// matrix lives in the `.tb.kt` beside it (`spec/matrix-files.md`).
package fixtures.unknownchild

sealed interface S {
    data object Idle : S
    data object Busy : S
}

sealed interface A {
    data object Go : A
}

sealed interface F {
    data object Note : F
}

class Ctx

/** An ordinary interface: no `@Machine`, so nothing to delegate to. */
interface NotAMachine
