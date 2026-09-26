//~ EXPECT: tabula::path-duplicate
//
// Two routes, one name.
//
// The shape a copied `@Path` leaves behind: the states were edited and the name
// was not. A narrowed call site names the path it narrows to, so two paths
// answering to one name is an ambiguity the generator cannot resolve.
package fixtures.pathduplicate

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
@Path("go", [S.Idle::class, A.Start::class, S.Busy::class, A.Start::class, S.Done::class])
@Path("go", [S.Busy::class, A.Start::class, S.Done::class])
//                     Start                                        Stop
@Row(S.Idle::class,  [CellSpec(Kind.HANDLE),                       CellSpec(Kind.IGNORE)])
@Row(S.Busy::class,  [CellSpec(Kind.GO, to = S.Done::class),       CellSpec(Kind.IGNORE)])
@Row(S.Done::class,  [CellSpec(Kind.IGNORE),                       CellSpec(Kind.IGNORE)])
interface Spec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
