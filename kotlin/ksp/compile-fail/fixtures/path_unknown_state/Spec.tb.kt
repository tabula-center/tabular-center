//~ EXPECT: tabula::path-unknown-state
//
// A route naming a state the machine never declared.
//
// `S.Gone` exists as a type and the `states` list omits it, which is the shape
// a rename leaves behind -- the IDE moves the `KClass` reference and the
// declaration list stays as it was.
package fixtures.pathunknownstate

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
@Path("gone", [S.Idle::class, S.Gone::class])
//                     Start                                        Stop
@Row(S.Idle::class,  [CellSpec(Kind.HANDLE),                       CellSpec(Kind.IGNORE)])
@Row(S.Busy::class,  [CellSpec(Kind.GO, to = S.Done::class),       CellSpec(Kind.IGNORE)])
@Row(S.Done::class,  [CellSpec(Kind.IGNORE),                       CellSpec(Kind.IGNORE)])
interface Spec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
