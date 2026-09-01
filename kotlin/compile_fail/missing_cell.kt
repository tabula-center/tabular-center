//~ EXPECT: class 'Hole' is not abstract and does not implement abstract base class member
//
// THE GUARANTEE, in Kotlin. `Running x Tick` is a HANDLE cell, so KSP emits an
// abstract member for it; omitting the override is a plain
// "does not implement abstract base class member" error from kotlinc.
//
// It rests on the oldest mechanism in the language, not on `when`
// exhaustiveness — which a developer could defeat with `else`, and which is
// why the dispatcher lives only in generated code.
package cf

import dev.tabula.*
import reference.*

class Hole : TimerMachine() {
    override suspend fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start): Step<S, F> =
        Step.Go(S.Running(0), listOf(F.StartClock))

    // runningTick is missing.

    override suspend fun startClock(ctx: Ctx, effect: F.StartClock): A? = null
    override suspend fun stopClock(ctx: Ctx, effect: F.StopClock): A? = null
}
