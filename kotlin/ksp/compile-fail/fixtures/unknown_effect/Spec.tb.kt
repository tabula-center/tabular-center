//~ EXPECT: tabula::unknown-effect
//
// A cell emitting an effect the machine never declared.
//
// `effects` is not documentation: it is what the generated `perform` switches
// over, so an effect outside it has no handler and no `when` arm. Declaring
// `Beep` and emitting `Whirr` is the shape a rename leaves behind.
package fixtures.unknowneffect

import dev.tabula.CellSpec
import dev.tabula.Kind
import dev.tabula.Machine
import dev.tabula.Row
import dev.tabula.Step

@Machine(
    states = [S.Idle::class, S.Busy::class],
    actions = [A.Start::class, A.Stop::class],
    effects = [F.Beep::class],
    initial = S.Idle::class,
)
//                       Start                                             Stop
@Row(S.Idle::class,    [CellSpec(Kind.EMIT, emit = [F.Whirr::class]),     CellSpec(Kind.IGNORE)])
@Row(S.Busy::class,    [CellSpec(Kind.IGNORE),                            CellSpec(Kind.HANDLE)])
interface Spec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
