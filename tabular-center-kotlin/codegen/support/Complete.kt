/**
 * A complete implementation of the generated Timer surface.
 *
 * Compiling this proves the emitted source is not merely well-formed but
 * usable: every member it demands can actually be satisfied.
 */
package generated.timer

import dev.tabula.Step

class Complete : Cells {
    override suspend fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start) =
        Step.Go(S.Running(0), listOf(F.StartClock))

    override suspend fun runningTick(ctx: Ctx, state: S.Running, action: A.Tick): Step<S, F> =
        if (action.now - state.since >= ctx.limit) Step.Go(S.Done, listOf(F.StopClock))
        else Step.Stay()

    override suspend fun startClock(ctx: Ctx, effect: F.StartClock): A? = null
    override suspend fun stopClock(ctx: Ctx, effect: F.StopClock): A? = null

    override suspend fun halt(ctx: Ctx, effect: F.Halt): A? = null
}
