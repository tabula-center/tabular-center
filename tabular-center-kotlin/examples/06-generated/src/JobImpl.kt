/**
 * One class satisfying BOTH machines' surfaces.
 *
 * The generated `generated.job.Cells` extends `generated.retry.Cells`, so a
 * hole anywhere in the child breaks this class -- the composition property,
 * through annotations this time. Nothing here was written by hand except the
 * bodies: the members, their names and their narrowed types all come from the
 * two `.tb.kt` files.
 */
package generated.job

import dev.tabula.Step

class JobImpl : Cells {
    // The child's cells, required through `generated.retry.Cells`.
    override fun readyAttempt(
        ctx: generated.retry.Ctx,
        state: generated.retry.S.Ready,
        action: generated.retry.A.Attempt,
    ): Step<generated.retry.S, generated.retry.F> =
        Step.Go(generated.retry.S.Waiting(1), listOf(generated.retry.F.Sleep))

    override fun waitingElapsed(
        ctx: generated.retry.Ctx,
        state: generated.retry.S.Waiting,
        action: generated.retry.A.Elapsed,
    ): Step<generated.retry.S, generated.retry.F> =
        if (state.attempt >= ctx.maxAttempts) {
            Step.Go(generated.retry.S.Exhausted, listOf(generated.retry.F.GiveUp))
        } else {
            Step.Go(generated.retry.S.Waiting(state.attempt + 1), listOf(generated.retry.F.Sleep))
        }

    override fun sleep(ctx: generated.retry.Ctx, effect: generated.retry.F.Sleep): generated.retry.A? =
        generated.retry.A.Elapsed

    override fun giveUp(ctx: generated.retry.Ctx, effect: generated.retry.F.GiveUp): generated.retry.A? = null

    // The parent's own cell and effect handler.
    override fun idleRun(ctx: Ctx, state: S.Idle, action: A.Run): Step<S, F> =
        Step.Go(S.Retrying(generated.retry.S.Ready), listOf(F.Log))

    override fun log(ctx: Ctx, effect: F.Log): A? = null

    // The action prisms: one per DELEGATE cell, the only per-cell part.
    override fun retryingRunToChild(ctx: Ctx, state: S.Retrying, action: A.Run): generated.retry.A? =
        generated.retry.A.Attempt

    override fun retryingTickToChild(ctx: Ctx, state: S.Retrying, action: A.Tick): generated.retry.A? =
        generated.retry.A.Elapsed

    // The lens: once per child, however many cells delegate.
    override fun retryChildState(state: S): generated.retry.S =
        (state as? S.Retrying)?.child ?: generated.retry.S.Ready

    override fun retryEmbed(state: S, child: generated.retry.S): S = S.Retrying(child)

    override fun retryLift(effect: generated.retry.F): F = F.Log

    override fun retryChildCtx(ctx: Ctx): generated.retry.Ctx = ctx.retry
}
