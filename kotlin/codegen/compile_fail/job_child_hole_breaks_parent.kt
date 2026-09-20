//~ EXPECT: does not implement abstract member
//
// THE COMPOSITION PROPERTY, AFTER GENERATION.
//
// The emitted `generated.job.Cells` refines the emitted `generated.retry.Cells`, so a
// hole in the CHILD's surface -- `waitingElapsed` below -- breaks any class
// implementing the PARENT. The generated twin of
// `compile_fail/child_hole_breaks_parent.kt`, which checks the hand-written
// composition.
package generated.job

import dev.tabula.Step

class Incomplete : Cells {
    override fun readyAttempt(ctx: generated.retry.Ctx, state: generated.retry.S.Ready, action: generated.retry.A.Attempt): Step<generated.retry.S, generated.retry.F> =
        Step.Ignored
    // waitingElapsed is missing -- a child cell.
    override fun sleep(ctx: generated.retry.Ctx, effect: generated.retry.F.Sleep): generated.retry.A? = null
    override fun giveUp(ctx: generated.retry.Ctx, effect: generated.retry.F.GiveUp): generated.retry.A? = null

    override fun idleRun(ctx: Ctx, state: S.Idle, action: A.Run): Step<S, F> = Step.Ignored
    override fun log(ctx: Ctx, effect: F.Log): A? = null
    override fun retryingRunToChild(ctx: Ctx, state: S.Retrying, action: A.Run): generated.retry.A? = null
    override fun retryingTickToChild(ctx: Ctx, state: S.Retrying, action: A.Tick): generated.retry.A? = null
    override fun retryChildState(state: S): generated.retry.S = generated.retry.S.Ready
    override fun retryEmbed(state: S, child: generated.retry.S): S = state
    override fun retryLift(effect: generated.retry.F): F = F.Log
    override fun retryChildCtx(ctx: Ctx): generated.retry.Ctx = ctx.retry
}
