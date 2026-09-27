// The machine, checked headlessly -- the same way every other Kotlin example
// is checked, through the generated dispatcher and with no toolkit involved.
//
// What this does NOT check is what is on the screen. `nix flake check` cannot
// open a window, and an example that implied otherwise would be overclaiming.
// The UI layer is COMPILED, which catches the thing worth catching: add a
// state or an action and `ConnectionStateMachine` stops compiling, because the
// generated `Cells` surface changed.
// No package: `Check` lives in the root package, and Kotlin cannot import
// from the root package into a named one. Every other example's checks sit
// here for the same reason.

import dev.tabularcenter.Step
import example.compose.ConnectionCells
import example.compose.connection.A
import example.compose.connection.Ctx
import example.compose.connection.F
import example.compose.connection.S
import example.compose.connection.perform
import example.compose.connection.step

fun main() {
    val log = mutableListOf<String>()
    val cells = ConnectionCells { log += it }
    val ctx = Ctx(now = { 7 })

    val started = step(cells, ctx, S.Idle, A.Start)
    Check.eq(started, Step.Go(S.Connecting, listOf(F.Dial)), "start dials")

    // The effect answers with a follow-up action, as a socket would.
    val follow = perform(cells, ctx, F.Dial)
    Check.eq(follow, A.Ready(at = 7), "dialling answers with Ready")
    Check.eq(log.toList(), listOf("dialling"), "the effect ran once")

    val live = step(cells, ctx, S.Connecting, A.Ready(at = 7))
    Check.eq(live, Step.Go(S.Live(since = 7)), "ready goes live, carrying the payload")

    // The table decides the rest: pressing a button in the wrong state is a
    // decision, not a bug to defend against in the UI.
    Check.eq(step(cells, ctx, S.Live(since = 7), A.Start), Step.Ignored, "Start in Live is ignored")
    Check.ok(step(cells, ctx, S.Failed, A.Retry) is Step.Go, "Failed retries")

    // Composition, in SessionCheck.kt: one runner, because the Gradle task
    // executes one main class and a check nobody runs is not a check.
    sessionChecks()
    checkoutChecks()

    Check.report("compose example")
}
