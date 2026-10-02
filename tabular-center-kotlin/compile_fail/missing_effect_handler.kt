//~ EXPECT: does not implement abstract member
//
// The effect surface, same mechanism. Add an effect variant to a shipped
// machine and every handler in the codebase stops compiling.
package cf

import center.tabula.*
import reference.*

class NoStop : TimerMachine() {
    override suspend fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start): Step<S, F> =
        Step.Stay()

    override suspend fun runningTick(ctx: Ctx, state: S.Running, action: A.Tick): Step<S, F> =
        Step.Stay()

    override suspend fun startClock(ctx: Ctx, effect: F.StartClock): A? = null
    // stopClock is missing.
}
