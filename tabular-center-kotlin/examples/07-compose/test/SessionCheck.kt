// Composition, checked through the generated dispatchers: the parent's, which
// contains the child's.
//
// Nothing here mentions Compose. The transition layer is testable without a
// toolkit, which is the reason a matrix is worth having at all.

import center.tabula.Step
import example.compose.ConnectionCells
import example.compose.SessionCells
import example.compose.connection.F as ChildF
import example.compose.connection.S as ChildS
import example.compose.session.A
import example.compose.session.Ctx
import example.compose.session.F
import example.compose.session.S
import example.compose.session.step

fun sessionChecks() {
    val log = mutableListOf<String>()
    val cells = SessionCells(ConnectionCells { log += it }) { log += it }
    val ctx = Ctx(connection = example.compose.connection.Ctx(now = { 3 }))

    Check.eq(
        step(cells, ctx, S.Booting, A.Boot),
        Step.Go(S.Running(ChildS.Idle)),
        "booting starts a session holding an idle connection",
    )

    // One parent action, narrowed by the prism to the child's `Start`, whose
    // cell is a GO emitting Dial -- and the parent sees its own effect, lifted.
    Check.eq(
        step(cells, ctx, S.Running(ChildS.Idle), A.Tap),
        Step.Go(S.Running(ChildS.Connecting), listOf(F.Note)),
        "a tap is delegated, and the child's effect is lifted to the parent's",
    )

    // The prism declines while the child is dialling: nothing to send, so the
    // parent ignores rather than inventing a transition.
    Check.eq(
        step(cells, ctx, S.Running(ChildS.Connecting), A.Tap),
        Step.Ignored,
        "a tap with nothing to delegate is ignored",
    )

    // The child's own payload survives the round trip through the parent.
    Check.eq(
        step(cells, ctx, S.Running(ChildS.Live(since = 3)), A.Tap),
        Step.Go(S.Running(ChildS.Idle), listOf(F.Note)),
        "dropping a live connection returns it to idle, inside the session",
    )

    Check.eq(
        step(cells, ctx, S.Running(ChildS.Idle), A.Finish),
        Step.Go(S.Ended, listOf(F.Note)),
        "the parent's own cell still decides its own actions",
    )
}
