/**
 * One type satisfying BOTH machines' generated surfaces: `Cells : retry.Cells`,
 * so implementing the parent requires implementing the child. The generated
 * twin of `test/Composition.kt`'s hand-written composition.
 */
package generated.job

import dev.tabula.Step

class CompleteJob : Cells {
    // The child's cells and effect handlers, required through `retry.Cells`.
    override fun readyAttempt(ctx: retry.Ctx, state: retry.S.Ready, action: retry.A.Attempt): Step<retry.S, retry.F> =
        Step.Go(retry.S.Waiting(1), listOf(retry.F.Sleep))

    override fun waitingElapsed(
        ctx: retry.Ctx,
        state: retry.S.Waiting,
        action: retry.A.Elapsed,
    ): Step<retry.S, retry.F> =
        if (state.attempt >= ctx.maxAttempts) Step.Go(retry.S.Exhausted, listOf(retry.F.GiveUp))
        else Step.Go(retry.S.Waiting(state.attempt + 1), listOf(retry.F.Sleep))

    override fun sleep(ctx: retry.Ctx, effect: retry.F.Sleep): retry.A? = retry.A.Elapsed
    override fun giveUp(ctx: retry.Ctx, effect: retry.F.GiveUp): retry.A? = null

    // The parent's own cell and effect handler.
    override fun idleRun(ctx: Ctx, state: S.Idle, action: A.Run): Step<S, F> =
        Step.Go(S.Retrying(retry.S.Ready), listOf(F.Log))

    override fun log(ctx: Ctx, effect: F.Log): A? = null

    // The action prisms, one per DELEGATE cell.
    override fun retryingRunToChild(ctx: Ctx, state: S.Retrying, action: A.Run): retry.A? = retry.A.Attempt
    override fun retryingTickToChild(ctx: Ctx, state: S.Retrying, action: A.Tick): retry.A? = retry.A.Elapsed

    // The lens, once per child.
    override fun retryChildState(state: S): retry.S = (state as? S.Retrying)?.child ?: retry.S.Ready
    override fun retryEmbed(state: S, child: retry.S): S = S.Retrying(child)
    override fun retryLift(effect: retry.F): F = F.Log
    override fun retryChildCtx(ctx: Ctx): retry.Ctx = ctx.retry
}

/** The dispatcher is callable with it, and reaches the child through the lens. */
fun driveJob(): Step<S, F> = step(CompleteJob(), Ctx(retry.Ctx(3)), S.Retrying(retry.S.Ready), A.Run)
