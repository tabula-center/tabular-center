//~ EXPECT: does not implement abstract member
//
// THE GUARANTEE SURVIVES GENERATION.
//
// This is the test the golden diff cannot do. Comparing characters proves the
// emitter is deterministic; compiling the output and then compiling THIS
// against it proves the output still enforces what the design promises.
//
// `runningTick` is a HANDLE cell in the emitted surface, and omitting it fails.
package generated.timer

import dev.tabula.Step

class Hole : Cells {
    override suspend fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start) =
        Step.Go(S.Running(0), listOf(F.StartClock))

    // runningTick is missing.

    override suspend fun startClock(ctx: Ctx, effect: F.StartClock): A? = null
    override suspend fun stopClock(ctx: Ctx, effect: F.StopClock): A? = null
}
