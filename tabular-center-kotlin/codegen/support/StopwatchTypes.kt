/**
 * The hand-written half of the stopwatch machine, and its implementation.
 *
 * The implementation lives HERE rather than in `Complete.kt`, unlike the
 * other two machines, because the generated surface is `internal`: `Complete.kt`
 * is compiled in a separate `kotlinc` invocation, which is a separate module,
 * and would not see it. Compiling the implementation alongside the emitted
 * source is what proves an internal machine is implementable at all.
 */
package generated.stopwatch

import dev.tabularcenter.Step

internal sealed interface S {
    data object Idle : S
    data class Running(val since: Long) : S
}

internal sealed interface A {
    data object Start : A
    data object Stop : A
}

internal sealed interface F {
    data object Beep : F
}

internal class Ctx {
    var lastElapsed: Long = -1
}

interface Clock {
    fun now(): Long
}

/** Every member an extension on `Clock`, as the prototype's receiver says. */
internal class StopwatchComplete : Cells {
    override fun Clock.idleStart(ctx: Ctx, state: S.Idle, action: A.Start): Step<S, F> =
        Step.Go(S.Running(now()))

    override fun Clock.runningStop(ctx: Ctx, state: S.Running, action: A.Stop): Step<S, F> {
        ctx.lastElapsed = now() - state.since
        return Step.Go(S.Idle, listOf(F.Beep))
    }

    override fun Clock.beep(ctx: Ctx, effect: F.Beep): A? = null
}

/** A caller, so the receiver requirement on `step` is exercised, not just declared. */
internal fun dispatchOnce(clock: Clock): Step<S, F> =
    with(clock) { step(StopwatchComplete(), Ctx(), S.Idle, A.Start) }
