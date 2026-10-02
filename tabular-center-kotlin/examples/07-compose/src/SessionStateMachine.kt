/**
 * The parent machine, nesting the child's screen inside its own.
 *
 * Two kinds of composition, one for each layer, and they line up:
 *
 * - the TRANSITION layer composes through `DELEGATE`: the parent's state
 *   contains the child's, and `SessionCells` extends the child's generated
 *   `Cells`, so a hole anywhere in the child breaks the parent;
 * - the UI layer composes bitkey's way: `model()` calling `model()`.
 *
 * Note what the nested screen may NOT do. Its buttons send the parent's
 * `A.Tap`, and the prism -- `runningTapToChild` -- decides which child action
 * that is, from the child's own state. The child's alphabet is never reached
 * into from the UI, so the matrix stays the only place a transition is decided.
 */
package example.compose

import androidx.compose.runtime.Composable
import center.tabula.Step
import example.compose.connection.Cells as ConnectionCellsSurface
import example.compose.session.A
import example.compose.session.Cells
import example.compose.session.Ctx
import example.compose.session.F
import example.compose.session.S
import center.tabula.Export
import example.compose.session.TABLE
import example.compose.session.perform
import example.compose.session.step
import example.compose.connection.A as ChildA
import example.compose.connection.Ctx as ChildCtx
import example.compose.connection.F as ChildF
import example.compose.connection.S as ChildS

/** What the session screen renders: its own text, and the child's model. */
data class SessionModel(
    val status: String,
    val connection: ConnectionModel?,
    val buttons: List<Button>,
    /** The PARENT's matrix. The child's comes with the nested model. */
    val grid: String,
) {
    data class Button(val label: String, val onClick: () -> Unit)
}

data class SessionProps(val now: () -> Int)

/** The nested screen: pure, because its state belongs to its parent. */
data class ConnectionScreenProps(val state: ChildS, val send: (ChildA) -> Unit)

class ConnectionScreen : StateMachine<ConnectionScreenProps, ConnectionModel> {
    @Composable
    override fun model(props: ConnectionScreenProps): ConnectionModel =
        connectionModel(props.state, props.send)
}

/**
 * One class satisfying both surfaces, the child's by forwarding.
 *
 * `Cells : ConnectionCellsSurface` is generated, not written here: the parent
 * declared a DELEGATE and the processor refined the interface. Forwarding to
 * the child's own implementation is the ordinary way to satisfy it -- and
 * deleting a line below stops this compiling, which is the composition
 * property arriving through annotations.
 */
class SessionCells(
    private val child: ConnectionCells,
    private val log: (String) -> Unit,
) : Cells, ConnectionCellsSurface by child {

    override fun bootingBoot(ctx: Ctx, state: S.Booting, action: A.Boot): Step<S, F> =
        Step.Go(S.Running(child = ChildS.Idle))

    // The prism: one parent action, narrowed by the child's state.
    override fun runningTapToChild(ctx: Ctx, state: S.Running, action: A.Tap): ChildA? =
        when (state.child) {
            is ChildS.Idle -> ChildA.Start
            is ChildS.Live -> ChildA.Drop
            is ChildS.Failed -> ChildA.Retry
            is ChildS.Connecting -> null // nothing to do while it dials
        }

    // The lens: once per child, however many cells delegate.
    override fun connectionChildState(state: S): ChildS =
        (state as? S.Running)?.child ?: ChildS.Idle

    override fun connectionEmbed(state: S, child: ChildS): S = S.Running(child)

    override fun connectionLift(effect: ChildF): F = F.Note

    override fun connectionChildCtx(ctx: Ctx): ChildCtx = ctx.connection

    override fun note(ctx: Ctx, effect: F.Note): A? {
        log("note")
        return null
    }
}

class SessionStateMachine(private val log: (String) -> Unit = {}) :
    StateMachine<SessionProps, SessionModel> {

    private val screen = ConnectionScreen()

    @Composable
    override fun model(props: SessionProps): SessionModel {
        val ctx = Ctx(connection = ChildCtx(props.now))
        val cells = SessionCells(ConnectionCells(log), log)
        val machine = rememberMachine<S, A, F>(
            initial = S.Booting,
            step = { s, a -> step(cells, ctx, s, a) },
            perform = { f -> perform(cells, ctx, f) },
        )

        val state = machine.state
        val child = if (state is S.Running) {
            // bitkey's nesting: the child's model, produced inside the
            // parent's. Its send goes back through the parent's matrix.
            screen.model(ConnectionScreenProps(state.child) { machine.send(A.Tap) })
        } else {
            null
        }

        return SessionModel(
            status = when (state) {
                is S.Booting -> "Booting"
                is S.Running -> "Session running"
                is S.Ended -> "Session ended"
            },
            connection = child,
            buttons = listOf(
                SessionModel.Button("Boot") { machine.send(A.Boot) },
                SessionModel.Button("Finish") { machine.send(A.Finish) },
            ),
            grid = Export.toGrid(TABLE),
        )
    }
}
