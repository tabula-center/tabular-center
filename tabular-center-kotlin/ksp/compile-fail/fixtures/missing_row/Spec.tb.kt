//~ EXPECT: tabular-center::missing-row
//
// Three declared states, two rows.
//
// The row that is missing is the LAST one, not the middle: a walk that stops
// when rows run out reports this, while one that indexes rows by state would
// report the middle case and silently accept a truncated table.
package fixtures.missingrow

import dev.tabularcenter.CellSpec
import dev.tabularcenter.Kind
import dev.tabularcenter.Machine
import dev.tabularcenter.Row
import dev.tabularcenter.Step

@Machine(
    states = [S.Idle::class, S.Busy::class, S.Done::class],
    actions = [A.Start::class, A.Stop::class],
    effects = [],
    initial = S.Idle::class,
)
//                     Start                    Stop
@Row(S.Idle::class,  [CellSpec(Kind.HANDLE),  CellSpec(Kind.IGNORE)])
@Row(S.Busy::class,  [CellSpec(Kind.IGNORE),  CellSpec(Kind.HANDLE)])
interface Spec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
