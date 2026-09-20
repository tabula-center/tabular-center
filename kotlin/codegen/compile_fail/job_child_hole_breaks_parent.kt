//~ EXPECT: does not implement abstract member
//
// THE COMPOSITION PROPERTY, AFTER GENERATION.
//
// The emitted `generated.job.Cells` refines the emitted `retry.Cells`, so a
// hole in the CHILD's surface -- `waitingElapsed` below -- breaks any class
// implementing the PARENT. The generated twin of
// `compile_fail/child_hole_breaks_parent.kt`, which checks the hand-written
// composition.
package generated.job

import dev.tabula.Step

class Incomplete : Cells {
    override fun readyAttempt(ctx: retry.Ctx, state: retry.S.Ready, action: retry.A.Attempt): Step<retry.S, retry.F> =
        Step.Ignored
    // waitingElapsed is missing -- a child cell.
    override fun sleep(ctx: retry.Ctx, effect: retry.F.Sleep): retry.A? = null
    override fun giveUp(ctx: retry.Ctx, effect: retry.F.GiveUp): retry.A? = null

    override fun idleRun(ctx: Ctx, state: S.Idle, action: A.Run): Step<S, F> = Step.Ignored
    override fun log(ctx: Ctx, effect: F.Log): A? = null
    override fun retryingRunToChild(ctx: Ctx, state: S.Retrying, action: A.Run): retry.A? = null
    override fun retryingTickToChild(ctx: Ctx, state: S.Retrying, action: A.Tick): retry.A? = null
    override fun retryChildState(state: S): retry.S = retry.S.Ready
    override fun retryEmbed(state: S, child: retry.S): S = state
    override fun retryLift(effect: retry.F): F = F.Log
    override fun retryChildCtx(ctx: Ctx): retry.Ctx = ctx.retry
}
