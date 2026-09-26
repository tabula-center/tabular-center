//~ EXPECT: tabula::unknown-state
//
// GO to a state the machine never declared.
//
// The one that would be silent without a check: `S.Parked` exists as a type,
// so the generated `when` arm compiles. The table would then carry a
// destination with no row, and the first thing to notice would be a runtime
// `IllegalStateException` from a dispatcher that is supposed to make those
// impossible.
package fixtures.unknownstate

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
//                       Start                                        Stop
@Row(S.Idle::class,    [CellSpec(Kind.GO, to = S.Parked::class),     CellSpec(Kind.IGNORE)])
@Row(S.Busy::class,    [CellSpec(Kind.IGNORE),                       CellSpec(Kind.HANDLE)])
interface Spec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
