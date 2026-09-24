/**
 * The matrix, in a file of its own: see `spec/matrix-files.md`.
 *
 * A connection: idle until asked, connecting until it is live or fails, and
 * retryable from failure. Four states, four actions, sixteen cells -- and the
 * point of the example is that every one of them is decided here, in the
 * table, rather than scattered across a Composable.
 */
package example.compose.connection

import dev.tabula.CellSpec
import dev.tabula.Kind
import dev.tabula.Machine
import dev.tabula.Row
import dev.tabula.Step

@Machine(
    states = [S.Idle::class, S.Connecting::class, S.Live::class, S.Failed::class],
    actions = [A.Start::class, A.Ready::class, A.Drop::class, A.Retry::class],
    effects = [F.Dial::class, F.Hangup::class],
    initial = S.Idle::class,
)
//                        Start                                                    Ready                                     Drop                                          Retry
@Row(S.Idle::class,      [CellSpec(Kind.GO, to = S.Connecting::class, emit = [F.Dial::class]),   CellSpec(Kind.IGNORE),                    CellSpec(Kind.IGNORE),                        CellSpec(Kind.IGNORE)])
@Row(S.Connecting::class,[CellSpec(Kind.IGNORE),                                                 CellSpec(Kind.HANDLE),                    CellSpec(Kind.GO, to = S.Failed::class),      CellSpec(Kind.IGNORE)])
@Row(S.Live::class,      [CellSpec(Kind.IGNORE),                                                 CellSpec(Kind.IGNORE),                    CellSpec(Kind.GO, to = S.Idle::class, emit = [F.Hangup::class]), CellSpec(Kind.IGNORE)])
@Row(S.Failed::class,    [CellSpec(Kind.IGNORE),                                                 CellSpec(Kind.IGNORE),                    CellSpec(Kind.IGNORE),                        CellSpec(Kind.GO, to = S.Connecting::class, emit = [F.Dial::class])])
interface ConnectionSpec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
