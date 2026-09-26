/**
 * A colorless child inside a colored parent: the allowed direction of color
 * flow. The child's cells stay plain -- they are `generated.retry.Cells`, exactly as in
 * CompleteJob -- while the parent's are `suspend`, and the parent's generated
 * `delegateToRetry` is a `suspend fun` calling the plain `generated.retry.step`.
 */
package generated.jobsuspend

import dev.tabula.Step

class CompleteJobSuspend : Cells {
    override fun readyAttempt(ctx: generated.retry.Ctx, state: generated.retry.S.Ready, action: generated.retry.A.Attempt): Step<generated.retry.S, generated.retry.F> =
        Step.Go(generated.retry.S.Waiting(1), listOf(generated.retry.F.Sleep))

    override fun waitingElapsed(
        ctx: generated.retry.Ctx,
        state: generated.retry.S.Waiting,
        action: generated.retry.A.Elapsed,
    ): Step<generated.retry.S, generated.retry.F> = Step.Go(generated.retry.S.Exhausted, listOf(generated.retry.F.GiveUp))

    override fun sleep(ctx: generated.retry.Ctx, effect: generated.retry.F.Sleep): generated.retry.A? = generated.retry.A.Elapsed
    override fun giveUp(ctx: generated.retry.Ctx, effect: generated.retry.F.GiveUp): generated.retry.A? = null

    override suspend fun idleRun(ctx: Ctx, state: S.Idle, action: A.Run): Step<S, F> =
        Step.Go(S.Retrying(generated.retry.S.Ready), listOf(F.Log))

    override suspend fun log(ctx: Ctx, effect: F.Log): A? = null

    override suspend fun retryingRunToChild(ctx: Ctx, state: S.Retrying, action: A.Run): generated.retry.A? =
        generated.retry.A.Attempt

    override suspend fun retryingTickToChild(ctx: Ctx, state: S.Retrying, action: A.Tick): generated.retry.A? =
        generated.retry.A.Elapsed

    override fun retryChildState(state: S): generated.retry.S = (state as? S.Retrying)?.child ?: generated.retry.S.Ready
    override fun retryEmbed(state: S, child: generated.retry.S): S = S.Retrying(child)
    override fun retryLift(effect: generated.retry.F): F = F.Log
    override fun retryChildCtx(ctx: Ctx): generated.retry.Ctx = ctx.retry
}

/** The color reaches the caller: driving the parent needs a coroutine. */
suspend fun driveJobSuspend(): Step<S, F> =
    step(CompleteJobSuspend(), Ctx(generated.retry.Ctx(3)), S.Retrying(generated.retry.S.Ready), A.Run)
