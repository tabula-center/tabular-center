// The matrix. `.tb.kt` so ktlint leaves the columns alone --
// `spec/matrix-files.md`, and `kotlin-matrix-stable` proves it.
package generated.gate

import center.tabula.CellSpec
import center.tabula.Emit
import center.tabula.Kind
import center.tabula.Machine
import center.tabula.Row
import center.tabula.Step

@Machine(
    states = [S.Closed::class, S.Opening::class, S.Open::class],
    actions = [A.Request::class, A.Arrived::class],
    effects = [F.Chime::class],
    initial = S.Closed::class,
)
//                          Request                                      Arrived
@Row(S.Closed::class,     [CellSpec(Kind.HANDLE),                       CellSpec(Kind.IGNORE)])
@Row(S.Opening::class,    [CellSpec(Kind.IGNORE),                       CellSpec(Kind.GO, to = S.Open::class, emits = [Emit(F.Chime::class, "volume = 3")])])
@Row(S.Open::class,       [CellSpec(Kind.GO, to = S.Closed::class),     CellSpec(Kind.IGNORE)])
interface GateSpec {
    suspend fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
