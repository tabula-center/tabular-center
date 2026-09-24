/**
 * The parent matrix: a session that contains a connection.
 *
 * `DELEGATE` hands one cell to the child machine. What the child is, where its
 * generated code lives, and what its types are called are all read by the
 * processor from `ConnectionSpec` itself -- a parent declares one thing about
 * its child, the class.
 */
package example.compose.session

import dev.tabula.CellSpec
import dev.tabula.Kind
import dev.tabula.Machine
import dev.tabula.Row
import dev.tabula.Step
import example.compose.connection.ConnectionSpec

@Machine(
    states = [S.Booting::class, S.Running::class, S.Ended::class],
    actions = [A.Boot::class, A.Tap::class, A.Finish::class],
    effects = [F.Note::class],
    initial = S.Booting::class,
)
//                        Boot                     Tap                                                 Finish
@Row(S.Booting::class,   [CellSpec(Kind.HANDLE),   CellSpec(Kind.IGNORE),                              CellSpec(Kind.IGNORE)])
@Row(S.Running::class,   [CellSpec(Kind.IGNORE),   CellSpec(Kind.DELEGATE, child = ConnectionSpec::class), CellSpec(Kind.GO, to = S.Ended::class, emit = [F.Note::class])])
@Row(S.Ended::class,     [CellSpec(Kind.IGNORE),   CellSpec(Kind.IGNORE),                              CellSpec(Kind.IGNORE)])
interface SessionSpec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
