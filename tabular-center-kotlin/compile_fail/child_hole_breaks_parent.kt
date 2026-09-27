//~ EXPECT: does not implement abstract member
//
// THE COMPOSITION PROPERTY:
//
//   Scoping a total child into a total parent yields a total parent, and the
//   compiler proves it by the same mechanism as everything else.
//
// `waitingElapsed` is a cell of the CHILD. The class here implements every
// cell of the PARENT and still fails, because `job.Cells : retry.Cells`.
//
// A hand-written HANDLE body could never give that: it is free to ignore the
// child, so no requirement would propagate and the hole would go unnoticed.
package cf3

import dev.tabularcenter.*
import composition.*

class ChildHole : job.Cells {
    override fun idleRun(ctx: job.Ctx, state: job.S.Idle, action: job.A.Run) =
        Step.Go(job.S.Retrying(retry.S.Ready), listOf(job.F.Log))

    override fun readyAttempt(ctx: retry.Ctx, state: retry.S.Ready, action: retry.A.Attempt) =
        Step.Go(retry.S.Waiting(1), listOf(retry.F.Sleep))

    // waitingElapsed is missing -- a CHILD cell.

    override fun retryingRunToChild(ctx: job.Ctx, state: job.S.Retrying, action: job.A.Run) =
        retry.A.Attempt
    override fun retryingTickToChild(ctx: job.Ctx, state: job.S.Retrying, action: job.A.Tick) =
        retry.A.Elapsed
    override fun retryChildState(state: job.S.Retrying) = state.child
    override fun retryEmbed(state: job.S.Retrying, child: retry.S): job.S = job.S.Retrying(child)
    override fun retryLift(effect: retry.F): job.F = job.F.Backoff
    override fun retryChildCtx(ctx: job.Ctx) = ctx.retry
}
