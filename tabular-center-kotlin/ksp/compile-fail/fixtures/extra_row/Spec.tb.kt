//~ EXPECT: tabular-center::extra-row
//
// A `@Row` for a state the machine never declared.
//
// The mirror of missing_row, and separate from it for the same reason the Rust
// pair is separate: `buildDesc` walks states and rows together, and the two
// arms that report a mismatch are reached at different points in that walk.
package fixtures.extrarow

import dev.tabula.CellSpec
import dev.tabula.Kind
import dev.tabula.Machine
import dev.tabula.Row
import dev.tabula.Step

@Machine(
    states = [S.Idle::class, S.Busy::class],
    actions = [A.Start::class, A.Stop::class],
    effects = [],
    initial = S.Idle::class,
)
//                     Start                    Stop
@Row(S.Idle::class,  [CellSpec(Kind.HANDLE),  CellSpec(Kind.IGNORE)])
@Row(S.Busy::class,  [CellSpec(Kind.IGNORE),  CellSpec(Kind.HANDLE)])
@Row(S.Gone::class,  [CellSpec(Kind.IGNORE),  CellSpec(Kind.IGNORE)])
interface Spec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
