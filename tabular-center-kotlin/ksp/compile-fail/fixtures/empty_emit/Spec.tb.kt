//~ EXPECT: tabular-center::empty-emit
//
// An EMIT cell that names no effect.
//
// EMIT without effects is IGNORE with extra words, and the diagnostic says so:
// a cell that stays put and does nothing has a spelling already. The effect
// type is non-empty here on purpose, so the failure is about the cell rather
// than about the machine having nothing to emit.
package fixtures.emptyemit

import dev.tabularcenter.CellSpec
import dev.tabularcenter.Kind
import dev.tabularcenter.Machine
import dev.tabularcenter.Row
import dev.tabularcenter.Step

@Machine(
    states = [S.Idle::class, S.Busy::class],
    actions = [A.Start::class, A.Stop::class],
    effects = [F.Beep::class],
    initial = S.Idle::class,
)
//                     Start                    Stop
@Row(S.Idle::class,  [CellSpec(Kind.HANDLE),  CellSpec(Kind.EMIT)])
@Row(S.Busy::class,  [CellSpec(Kind.IGNORE),  CellSpec(Kind.HANDLE)])
interface Spec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
