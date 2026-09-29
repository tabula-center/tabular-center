/**
 * A complete implementation of the rendering twin: every cell, every effect,
 * and every state's renderer.
 *
 * The cell half is `Complete`'s, verbatim -- the transitions are the Timer's
 * and still `suspend`. The render half is plain: the rendering prototype has
 * its own color, and here it has none. Each renderer receives its state
 * narrowed, so `renderRunning` reads `state.since` with no cast.
 */
package generated.timerrender

import dev.tabularcenter.Step

class CompleteRender : Cells, Renders {
    override suspend fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start) =
        Step.Go(S.Running(0), listOf(F.StartClock))

    override suspend fun runningTick(ctx: Ctx, state: S.Running, action: A.Tick): Step<S, F> =
        if (action.now - state.since >= ctx.limit) Step.Go(S.Done, listOf(F.StopClock))
        else Step.Stay()

    override suspend fun startClock(ctx: Ctx, effect: F.StartClock): A? = null
    override suspend fun stopClock(ctx: Ctx, effect: F.StopClock): A? = null

    override suspend fun halt(ctx: Ctx, effect: F.Halt): A? = null

    override fun renderIdle(state: S.Idle): String = "idle"
    override fun renderRunning(state: S.Running): String = "running since ${state.since}"
    override fun renderDone(state: S.Done): String = "done"
}
