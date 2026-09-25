/**
 * The parent matrix: a session that contains a connection.
 *
 * `DELEGATE` hands one cell to the child machine, and names it by its
 * annotated declaration. Everything else about the child -- its package, its
 * types, its context -- the processor reads from that class.
 */
package example.compose.session

import dev.tabula.CellSpec as C
import dev.tabula.Kind.DELEGATE
import dev.tabula.Kind.GO
import dev.tabula.Kind.HANDLE
import dev.tabula.Kind.IGNORE
import dev.tabula.Machine
import dev.tabula.Row
import dev.tabula.Step
import example.compose.connection.ConnectionSpec
import example.compose.session.A.Boot
import example.compose.session.A.Finish
import example.compose.session.A.Tap
import example.compose.session.F.Note
import example.compose.session.S.Booting
import example.compose.session.S.Ended
import example.compose.session.S.Running

@Machine(
    states = [Booting::class, Running::class, Ended::class],
    actions = [Boot::class, Tap::class, Finish::class],
    effects = [Note::class],
    initial = Booting::class,
)
//                    Boot       Tap                                         Finish
@Row(Booting::class, [C(HANDLE), C(IGNORE),                                  C(IGNORE)])
@Row(Running::class, [C(IGNORE), C(DELEGATE, child = ConnectionSpec::class), C(GO, to = Ended::class, emit = [Note::class])])
@Row(Ended::class,   [C(IGNORE), C(IGNORE),                                  C(IGNORE)])
interface SessionSpec {
    fun handle(ctx: Ctx, state: S, action: A): Step<S, F>
}
