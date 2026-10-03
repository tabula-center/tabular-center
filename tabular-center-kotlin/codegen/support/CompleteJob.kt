/**
 * One type satisfying BOTH machines' generated surfaces: `Cells : generated.retry.Cells`,
 * so implementing the parent requires implementing the child. The generated
 * twin of `test/Composition.kt`'s hand-written composition.
 */
package generated.job

import center.tabula.Step

class CompleteJob : Cells {
    override fun readyAttempt(ctx: generated.retry.Ctx, state: generated.retry.S.Ready, action: generated.retry.A.Attempt): Step<generated.retry.S, generated.retry.F> =
        Step.Go(generated.retry.S.Waiting(1), listOf(generated.retry.F.Sleep))

    override fun waitingElapsed(
        ctx: generated.retry.Ctx,
        state: generated.retry.S.Waiting,
        action: generated.retry.A.Elapsed,
    ): Step<generated.retry.S, generated.retry.F> =
        if (state.attempt >= ctx.maxAttempts) Step.Go(generated.retry.S.Exhausted, listOf(generated.retry.F.GiveUp))
        else Step.Go(generated.retry.S.Waiting(state.attempt + 1), listOf(generated.retry.F.Sleep))

    override fun sleep(ctx: generated.retry.Ctx, effect: generated.retry.F.Sleep): generated.retry.A? = generated.retry.A.Elapsed
    override fun giveUp(ctx: generated.retry.Ctx, effect: generated.retry.F.GiveUp): generated.retry.A? = null

    override fun idleRun(ctx: Ctx, state: S.Idle, action: A.Run): Step<S, F> =
        Step.Go(S.Retrying(generated.retry.S.Ready), listOf(F.Log))

    override fun log(ctx: Ctx, effect: F.Log): A? = null

    override fun retryingRunToChild(ctx: Ctx, state: S.Retrying, action: A.Run): generated.retry.A? = generated.retry.A.Attempt
    override fun retryingTickToChild(ctx: Ctx, state: S.Retrying, action: A.Tick): generated.retry.A? = generated.retry.A.Elapsed

    override fun retryChildState(state: S): generated.retry.S = (state as? S.Retrying)?.child ?: generated.retry.S.Ready
    override fun retryEmbed(state: S, child: generated.retry.S): S = S.Retrying(child)
    override fun retryLift(effect: generated.retry.F): F = F.Log
    override fun retryChildCtx(ctx: Ctx): generated.retry.Ctx = ctx.retry
}

fun driveJob(): Step<S, F> = step(CompleteJob(), Ctx(generated.retry.Ctx(3)), S.Retrying(generated.retry.S.Ready), A.Run)
