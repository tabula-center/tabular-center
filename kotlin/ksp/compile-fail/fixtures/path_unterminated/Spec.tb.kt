//~ EXPECT: tabula::path-unterminated
//
// A route that stops somewhere the machine can still leave.
//
// `Busy` has a GO to `Done`, so ending a path there describes a spine that is
// not finished. A path that never ends is a loop with a name.
package fixtures.pathunterminated

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
@Path("half", [S.Idle::class, S.Busy::class])
//                     Start                                        Stop
@Row(S.Idle::class,  [CellSpec(Kind.HANDLE),                       CellSpec(Kind.IGNORE)])
@Row(S.Busy::class,  [CellSpec(Kind.GO, to = S.Done::class),       CellSpec(Kind.IGNORE)])
@Row(S.Done::class,  [CellSpec(Kind.IGNORE),                       CellSpec(Kind.IGNORE)])
interface Spec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
