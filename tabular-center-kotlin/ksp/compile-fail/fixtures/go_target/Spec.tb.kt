//~ EXPECT: tabular-center::go-target
//
// GO to a state that carries a payload, with no literal arguments.
//
// Rule R3 in `spec/diagnostics.md`, and the one diagnostic here that exists to
// stop a shortcut rather than to catch a typo. Without it GO becomes the lazy
// option: every payload fills with zero values chosen to avoid writing a cell,
// and the machine's types stop meaning anything. `HANDLE`, or
// `CellSpec(Kind.GO, to = S.Running::class, args = "(0)")`, are the two honest
// answers and the message names both.
package fixtures.gotarget

import center.tabula.CellSpec
import center.tabula.Kind
import center.tabula.Machine
import center.tabula.Row
import center.tabula.Step

@Machine(
    states = [S.Idle::class, S.Running::class],
    actions = [A.Start::class, A.Stop::class],
    effects = [],
    initial = S.Idle::class,
)
//                        Start                                          Stop
@Row(S.Idle::class,     [CellSpec(Kind.GO, to = S.Running::class),      CellSpec(Kind.IGNORE)])
@Row(S.Running::class,  [CellSpec(Kind.IGNORE),                         CellSpec(Kind.HANDLE)])
interface Spec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
