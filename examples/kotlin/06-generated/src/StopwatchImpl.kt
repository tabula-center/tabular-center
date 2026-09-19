// The two cells a developer writes, and the one effect handler. Each is an
// extension on `Clock`, so `now()` is simply in scope.
package generated.stopwatch

import dev.tabula.Step

internal class StopwatchImpl : Cells {
    override fun Clock.idleStart(ctx: Ctx, state: S.Idle, action: A.Start): Step<S, F> =
        Step.Go(S.Running(now()))

    override fun Clock.runningStop(ctx: Ctx, state: S.Running, action: A.Stop): Step<S, F> {
        ctx.lastElapsed = now() - state.since
        return Step.Go(S.Idle, listOf(F.Beep))
    }

    override fun Clock.beep(ctx: Ctx, effect: F.Beep): A? {
        ctx.beeps++
        return null
    }
}
