/**
 * A colorless child inside a colored parent: the allowed direction of color
 * flow. The child's cells stay plain -- they are `retry.Cells`, exactly as in
 * CompleteJob -- while the parent's are `suspend`, and the parent's generated
 * `delegateToRetry` is a `suspend fun` calling the plain `retry.step`.
 */
package generated.jobsuspend

import dev.tabula.Step

class CompleteJobSuspend : Cells {
    override fun readyAttempt(ctx: retry.Ctx, state: retry.S.Ready, action: retry.A.Attempt): Step<retry.S, retry.F> =
        Step.Go(retry.S.Waiting(1), listOf(retry.F.Sleep))

    override fun waitingElapsed(
        ctx: retry.Ctx,
        state: retry.S.Waiting,
        action: retry.A.Elapsed,
    ): Step<retry.S, retry.F> = Step.Go(retry.S.Exhausted, listOf(retry.F.GiveUp))

    override fun sleep(ctx: retry.Ctx, effect: retry.F.Sleep): retry.A? = retry.A.Elapsed
    override fun giveUp(ctx: retry.Ctx, effect: retry.F.GiveUp): retry.A? = null

    override suspend fun idleRun(ctx: Ctx, state: S.Idle, action: A.Run): Step<S, F> =
        Step.Go(S.Retrying(retry.S.Ready), listOf(F.Log))

    override suspend fun log(ctx: Ctx, effect: F.Log): A? = null

    override suspend fun retryingRunToChild(ctx: Ctx, state: S.Retrying, action: A.Run): retry.A? =
        retry.A.Attempt

    override suspend fun retryingTickToChild(ctx: Ctx, state: S.Retrying, action: A.Tick): retry.A? =
        retry.A.Elapsed

    override fun retryChildState(state: S): retry.S = (state as? S.Retrying)?.child ?: retry.S.Ready
    override fun retryEmbed(state: S, child: retry.S): S = S.Retrying(child)
    override fun retryLift(effect: retry.F): F = F.Log
    override fun retryChildCtx(ctx: Ctx): retry.Ctx = ctx.retry
}

/** The color reaches the caller: driving the parent needs a coroutine. */
suspend fun driveJobSuspend(): Step<S, F> =
    step(CompleteJobSuspend(), Ctx(retry.Ctx(3)), S.Retrying(retry.S.Ready), A.Run)
