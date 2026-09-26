// The matrix. `.tb.kt` so ktlint leaves the columns alone --
// `spec/matrix-files.md`, and `kotlin-matrix-stable` proves it.
package generated.stopwatch

import dev.tabula.CellSpec
import dev.tabula.Kind
import dev.tabula.Machine
import dev.tabula.Row
import dev.tabula.Step

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
    /**
     * `Clock.` is the whole fixture, as `suspend` is Gate's.
     *
     * The generator copies the receiver onto every member it emits, the same
     * way it copies modifiers: it does not know what a `Clock` is and does not
     * need to. `internal` on the interface above is the other half -- the
     * generated surface takes its visibility from here.
     */
    fun Clock.handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
