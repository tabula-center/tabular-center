//~ EXPECT: tabular-center::row-arity
//~ AT: @Row(S.Idle::class
//
// A row with two cells against three actions.
//
// The first KSP diagnostic to get a UI test. Every one of these rules is
// already unit-tested in `codegen/Tests.kt`, which drives `buildDesc`
// directly -- what was missing is the diagnostic as a user meets it: emitted
// by the processor, through a real compilation, failing the build. `buildDesc`
// throwing a `TabularCenterError` and the processor turning that into a
// `KSPLogger.error` are different steps, and nothing exercised the second.
//
// `.tb.kt` because the rows below are column-aligned and a formatter's job is
// to normalise exactly that. See `spec/matrix-files.md`.
package fixtures.rowarity

import center.tabula.CellSpec
import center.tabula.Kind
import center.tabula.Machine
import center.tabula.Row
import center.tabula.Step

@Machine(
    states = [S.Idle::class, S.Busy::class],
    actions = [A.Start::class, A.Stop::class, A.Poke::class],
    effects = [],
    initial = S.Idle::class,
)
//                    Start                    Stop                     Poke
@Row(S.Idle::class, [CellSpec(Kind.HANDLE),  CellSpec(Kind.IGNORE)])
@Row(S.Busy::class, [CellSpec(Kind.IGNORE),  CellSpec(Kind.HANDLE),   CellSpec(Kind.IGNORE)])
interface BadSpec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
