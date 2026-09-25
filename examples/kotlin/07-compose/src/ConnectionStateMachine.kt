/**
 * The machine, in bitkey's shape: props in, model out, state held by the
 * Compose runtime.
 *
 * What tabula contributes is the `Cells` implementation below. Every cell of
 * the matrix that needs code is a member of it, so a state or an action added
 * to `Machine.tb.kt` stops this file compiling until it is decided -- which is
 * the whole claim, landing on an architecture that was not designed for it.
 */
package example.compose

import androidx.compose.runtime.Composable
import dev.tabula.Step
import example.compose.connection.A
import example.compose.connection.Cells
import example.compose.connection.Ctx
import example.compose.connection.F
import example.compose.connection.S
import dev.tabula.Export
import example.compose.connection.TABLE
import example.compose.connection.perform
import example.compose.connection.step

/** What the UI renders. Strings and callbacks: no state type escapes. */
data class ConnectionModel(
    val status: String,
    val detail: String,
    val buttons: List<Button>,
    /**
     * The matrix this screen is running, rendered.
     *
     * `TABLE` is inert data the processor generated beside the dispatcher, so
     * a screen can show the machine it runs. Change a cell in `Machine.tb.kt`
     * and this changes with it: the picture and the dispatch come from one
     * table, rather than from a diagram someone has to keep current.
     */
    val grid: String,
) {
    data class Button(val label: String, val onClick: () -> Unit)
}

/** What the machine is given. A clock, and nothing else here. */
data class ConnectionProps(val now: () -> Int)

/**
 * The cells. One member per non-static cell of the matrix, and the effect
 * handlers.
 *
 * `connectingReady` is the only cell the table leaves to code: everything else
 * is a GO or an IGNORE, decided in the table where a reader can see it.
 */
class ConnectionCells(private val log: (String) -> Unit) : Cells {
    override fun connectingReady(ctx: Ctx, state: S.Connecting, action: A.Ready): Step<S, F> =
        Step.Go(S.Live(since = action.at))

    override fun dial(ctx: Ctx, effect: F.Dial): A? {
        log("dialling")
        // A real one would connect and answer later; answering here keeps the
        // example honest about the shape: an effect may produce a follow-up
        // action, and the driver enqueues it rather than recursing.
        return A.Ready(at = ctx.now())
    }

    override fun hangup(ctx: Ctx, effect: F.Hangup): A? {
        log("hung up")
        return null
    }
}

class ConnectionStateMachine(
    private val log: (String) -> Unit = {},
) : StateMachine<ConnectionProps, ConnectionModel> {

    @Composable
    override fun model(props: ConnectionProps): ConnectionModel {
        val ctx = Ctx(props.now)
        val cells = ConnectionCells(log)
        val machine = rememberMachine<S, A, F>(
            initial = S.Idle,
            step = { s, a -> step(cells, ctx, s, a) },
            perform = { f -> perform(cells, ctx, f) },
        )

        return connectionModel(machine.state, machine.send)
    }
}

/**
 * How a connection state is described to a human, and nothing else.
 *
 * A pure function, so both screens share it: this one, which owns its state,
 * and the nested one in `SessionStateMachine`, whose state belongs to its
 * parent. The `when` is over the MODEL -- it decides what to show, never what
 * happens next -- and it is exhaustive because `S` is sealed, so a new state
 * stops this compiling too.
 */
fun connectionModel(state: S, send: (A) -> Unit): ConnectionModel {
    val (status, detail) = when (state) {
        is S.Idle -> "Idle" to "Nothing connected."
        is S.Connecting -> "Connecting" to "Dialling..."
        is S.Live -> "Live" to "Connected at ${state.since}."
        is S.Failed -> "Failed" to "The connection dropped."
    }

    return ConnectionModel(
        status = status,
        detail = detail,
        buttons = listOf(
            ConnectionModel.Button("Start") { send(A.Start) },
            ConnectionModel.Button("Drop") { send(A.Drop) },
            ConnectionModel.Button("Retry") { send(A.Retry) },
        ),
        grid = Export.toGrid(TABLE),
    )
}
