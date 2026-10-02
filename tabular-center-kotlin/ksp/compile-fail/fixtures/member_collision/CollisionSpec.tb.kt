//~ EXPECT: tabular-center::member-collision
//~ AT: @Row(S.Log::class
//
// Two cells the generator would give one name. A HANDLE cell's member is
// `lower(state) + Cap(action)`, a concatenation with nothing between the parts
// -- `hadilq/happy` flattens the same way -- so `(LogIn, Start)` and
// `(Log, InStart)` both become `logInStart`. In Kotlin that would even compile,
// as two overloads; refused anyway, because two unrelated `logInStart`s on one
// interface are a trap, and because in Swift it does not compile at all.
// Positioned at the second of the two cells to be named.
//
// `.tb.kt` because the rows are column-aligned. See `spec/matrix-files.md`.
package fixtures.membercollision

import center.tabula.CellSpec
import center.tabula.Kind
import center.tabula.Machine
import center.tabula.Row
import center.tabula.Step

@Machine(
    states = [S.LogIn::class, S.Log::class],
    actions = [A.Start::class, A.InStart::class],
    effects = [],
    initial = S.LogIn::class,
)
//                      Start                    InStart
@Row(S.LogIn::class, [CellSpec(Kind.HANDLE),  CellSpec(Kind.IGNORE)])
@Row(S.Log::class,   [CellSpec(Kind.IGNORE),  CellSpec(Kind.HANDLE)])
interface CollisionSpec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
