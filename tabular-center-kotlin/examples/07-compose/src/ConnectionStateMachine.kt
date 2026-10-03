/**
 * The machine, in bitkey's shape: props in, model out, state held by the
 * Compose runtime.
 *
 * What tabular-center contributes is the `Cells` implementation below. Every cell of
 * the matrix that needs code is a member of it, so a state or an action added
 * to `Machine.tb.kt` stops this file compiling until it is decided -- which is
 * the whole claim, landing on an architecture that was not designed for it.
 */
package example.compose

import androidx.compose.runtime.Composable
import center.tabula.Step
import example.compose.connection.A
import example.compose.connection.Cells
import example.compose.connection.Ctx
import example.compose.connection.F
import example.compose.connection.Renders
import example.compose.connection.S
import example.compose.connection.render
import center.tabula.Export
import example.compose.connection.TABLE
import example.compose.connection.perform
import example.compose.connection.step

/** What the UI renders. Strings and callbacks: no state type escapes. */
data class ConnectionModel(
    val status: String,
    val detail: String,
    val buttons: List<Button>,
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
 * How each connection state is described to a human, and nothing else.
 *
 * The machine's rendering surface (ARCHITECTURE §9): `Machine.tb.kt` declares
 * a `render` prototype, and the generator requires one member per state, each
 * receiving its state narrowed -- `renderLive` reads `state.since` with no
 * cast. This was a hand-written `when` over `S`. The `when` was exhaustive
 * too, but it was a convention this file kept; now it is a surface the
 * generator owns, so a new state fails here the same way a new cell fails in
 * `ConnectionCells`.
 */
object ConnectionDescriptions : Renders {
    override fun renderIdle(state: S.Idle): Pair<String, String> = "Idle" to "Nothing connected."
    override fun renderConnecting(state: S.Connecting): Pair<String, String> = "Connecting" to "Dialling..."
    override fun renderLive(state: S.Live): Pair<String, String> = "Live" to "Connected at ${state.since}."
    override fun renderFailed(state: S.Failed): Pair<String, String> = "Failed" to "The connection dropped."
}

fun connectionModel(state: S, send: (A) -> Unit): ConnectionModel {
    val (status, detail) = render(ConnectionDescriptions, state)

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
