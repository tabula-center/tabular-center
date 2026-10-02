// The types the fixture's matrix refers to. Ordinary Kotlin, formatted
// normally.
//
// The matrix itself is in `BadSpec.tb.kt` next to this file, and the split is
// not decoration: `kotlin-matrix-stable` caught this file the first time it
// ran, because it held an aligned matrix outside the `[*.tb.kt]` exemption in
// .editorconfig and ktlint collapsed the columns. Third time the convention
// has been learned the hard way in this repository -- `ReferenceTimer.kt`, the
// `06-generated` example, and now here -- which is the argument for the check
// that keeps finding it.
package fixtures.rowarity

import center.tabula.Step

sealed interface S {
    data object Idle : S
    data object Busy : S
}

sealed interface A {
    data object Start : A
    data object Stop : A
    data object Poke : A
}

sealed interface F

class Ctx

/** The prototype, kept beside the types so the matrix file holds only rows. */
interface Prototype {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
