//~ EXPECT: class 'Blank' is not abstract and does not implement abstract member
//
// THE RENDERING SURFACE HAS THE SAME GUARANTEE AS THE CELLS.
//
// One required member per state: a state with no renderer does not compile,
// exactly as a HANDLE cell with no handler does not. The cell half below is
// complete -- `CompleteRender`'s, verbatim -- so the one thing this can be
// refused for is the renderer it leaves out.
package generated.timerrender

import center.tabula.Step

class Blank : Cells, Renders {
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
}
