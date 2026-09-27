//~ EXPECT: tabular-center::path-broken
//
// A hop naming a cell that cannot reach where the hop says.
//
// Cell (Busy, Start) is `GO(Done)`, and the hop claims `Busy -Start-> Idle`.
// Because the path names the ACTION, this checks that one cell rather than
// asking whether anything in row `Busy` reaches `Idle` -- the imprecision a
// states-only spine could not avoid.
//
// This is the check that lets a path be declared away from the rows it
// describes. Without it the objection to a separate `@Path` annotation would
// stand: a route stated where a matrix reader will not look could drift from
// the matrix silently.
package fixtures.pathbroken

import dev.tabula.CellSpec
import dev.tabula.Kind
import dev.tabula.Machine
import dev.tabula.Path
import dev.tabula.Row
import dev.tabula.Step

@Machine(
    states = [S.Idle::class, S.Busy::class, S.Done::class],
    actions = [A.Start::class, A.Stop::class],
    effects = [],
    initial = S.Idle::class,
)
@Path("back", [S.Busy::class, A.Start::class, S.Idle::class])
//                     Start                                        Stop
@Row(S.Idle::class,  [CellSpec(Kind.HANDLE),                       CellSpec(Kind.IGNORE)])
@Row(S.Busy::class,  [CellSpec(Kind.GO, to = S.Done::class),       CellSpec(Kind.IGNORE)])
@Row(S.Done::class,  [CellSpec(Kind.IGNORE),                       CellSpec(Kind.IGNORE)])
interface Spec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
