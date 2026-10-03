// The matrix. `.tb.kt` so ktlint leaves the columns alone --
// `spec/matrix-files.md`, and `kotlin-matrix-stable` proves it.
package generated.stopwatch

import center.tabula.CellSpec
import center.tabula.Kind
import center.tabula.Machine
import center.tabula.Row
import center.tabula.Step

@Machine(
    states = [S.Idle::class, S.Running::class],
    actions = [A.Start::class, A.Stop::class],
    effects = [F.Beep::class],
    initial = S.Idle::class,
)
//                         Start                    Stop
@Row(S.Idle::class,      [CellSpec(Kind.HANDLE),  CellSpec(Kind.IGNORE)])
@Row(S.Running::class,   [CellSpec(Kind.IGNORE),  CellSpec(Kind.HANDLE)])
internal interface StopwatchSpec {
    fun Clock.handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
