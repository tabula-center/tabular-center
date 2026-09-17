// The matrix. `.tb.kt` so ktlint leaves the columns alone --
// `spec/matrix-files.md`, and `kotlin-matrix-stable` proves it.
package generated.gate

import dev.tabula.CellSpec
import dev.tabula.Kind
import dev.tabula.Machine
import dev.tabula.Row
import dev.tabula.Step

@Machine(
    states = [S.Closed::class, S.Opening::class, S.Open::class],
    actions = [A.Request::class, A.Arrived::class],
    effects = [F.Chime::class],
    initial = S.Closed::class,
)
//                          Request                                      Arrived
@Row(S.Closed::class,     [CellSpec(Kind.HANDLE),                       CellSpec(Kind.IGNORE)])
@Row(S.Opening::class,    [CellSpec(Kind.IGNORE),                       CellSpec(Kind.GO, to = S.Open::class, emit = [F.Chime::class])])
@Row(S.Open::class,       [CellSpec(Kind.GO, to = S.Closed::class),     CellSpec(Kind.IGNORE)])
interface GateSpec {
    /**
     * `suspend`, and that single keyword is the whole fixture.
     *
     * The generator copies prototype modifiers onto every member it emits --
     * the `Cells` methods, the effect handlers, `step` and `perform` alike --
     * so this machine's entire generated surface is suspending. Nothing in the
     * library enumerates `suspend`; it is copied, which is why a future
     * modifier needs no change here.
     */
    suspend fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
