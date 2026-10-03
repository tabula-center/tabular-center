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

fun connectHappily(cells: Cells, ctx: Ctx, arrived: A): String {
    val connecting = cells.idleStart(ctx, S.Idle, A.Start) elvis { return "stayed idle" }
    val (live, effects) = cells.connectingReady(ctx, connecting.state, arrived).elvis(
        Idle = { return "back to idle" },
        Connecting = { return "still connecting" },
        Failed = { return "failed, with ${it.effects.size} effect(s) to run" },
    )
    return "live ($live), with ${effects.size} effect(s) to run"
}
