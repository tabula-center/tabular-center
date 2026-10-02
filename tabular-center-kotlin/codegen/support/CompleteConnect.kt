/**
 * The `connect` machine, implemented, and its narrowed surface at a call site.
 *
 * Only one cell needs code: `(Connecting, Drop)`, the HANDLE the path does not
 * name. The two hops were HANDLEs too, and derivation made them GOs.
 */
package generated.connect

import center.tabula.Step

class CompleteConnect : Cells {
    override fun connectingDrop(ctx: Ctx, state: S.Connecting, action: A.Drop): Step<S, F> =
        Step.Go(S.Failed, listOf(F.Banner))

    override fun banner(ctx: Ctx, effect: F.Banner): A? = null
}

/**
 * The happy path reads straight down; each corner case is a named, required
 * handler, and `return` leaves this function from inside one -- `elvis` is
 * `inline`. Effects come back with the state, for the caller to run.
 */
fun connectHappily(cells: Cells, ctx: Ctx, arrived: A): String {
    // One alternative (Start in Idle goes to Connecting, or nothing happens):
    // infix, with a trailing lambda.
    val connecting = cells.idleStart(ctx, S.Idle, A.Start) elvis { return "stayed idle" }
    // Drop is a HANDLE, so Connecting can end anywhere: every other state is
    // a required, named handler.
    val (live, effects) = cells.connectingReady(ctx, connecting.state, arrived).elvis(
        Idle = { return "back to idle" },
        Connecting = { return "still connecting" },
        Failed = { return "failed, with ${it.effects.size} effect(s) to run" },
    )
    return "live ($live), with ${effects.size} effect(s) to run"
}
