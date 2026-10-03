/**
 * **2. Payloads and effects.**
 *
 * Payloads on both a state and an action, which is what makes narrowed cell
 * arguments worth having: `runningTick` receives `S.Running` and `A.Tick`, so
 * `state.since` and `action.now` are plain fields.
 */
package examples.timer

import center.tabula.Step

sealed interface S {
    data object Idle : S
    data class Running(val since: Long) : S
    data object Done : S
}

sealed interface A {
    data object Start : A
    data class Tick(val now: Long) : A
    data object Cancel : A
}

/** Why a clock stopped. `StopClock` is emitted from two different places. */
enum class Reason { Cancelled, Elapsed }

sealed interface F {
    data object StartClock : F
    data class StopClock(val reason: Reason) : F
}

class Ctx(val limit: Long) {
    val log = mutableListOf<String>()
}

interface Cells {
    fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start): Step<S, F>
    fun runningTick(ctx: Ctx, state: S.Running, action: A.Tick): Step<S, F>

    fun startClock(ctx: Ctx, effect: F.StartClock): A?
    fun stopClock(ctx: Ctx, effect: F.StopClock): A?
}

fun step(cells: Cells, ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
    is S.Idle -> when (a) {
        is A.Start -> cells.idleStart(ctx, s, a)
        is A.Tick -> Step.Ignored
        is A.Cancel -> Step.Ignored
    }
    is S.Running -> when (a) {
        is A.Start -> Step.Ignored
        is A.Tick -> cells.runningTick(ctx, s, a)
        is A.Cancel -> Step.Go(S.Idle, listOf(F.StopClock(Reason.Cancelled)))
    }
    is S.Done -> when (a) {
        is A.Start -> Step.Go(S.Running(0), listOf(F.StartClock))
        is A.Tick -> Step.Ignored
        is A.Cancel -> Step.Ignored
    }
}

fun perform(cells: Cells, ctx: Ctx, f: F): A? = when (f) {
    is F.StartClock -> cells.startClock(ctx, f)
    is F.StopClock -> cells.stopClock(ctx, f)
}

class Impl : Cells {
    override fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start) =
        Step.Go(S.Running(0), listOf(F.StartClock))

    override fun runningTick(ctx: Ctx, state: S.Running, action: A.Tick): Step<S, F> =
        if (action.now - state.since >= ctx.limit) {
            Step.Go(S.Done, listOf(F.StopClock(Reason.Elapsed)))
        } else {
            Step.Stay()
        }

    override fun startClock(ctx: Ctx, effect: F.StartClock): A? {
        ctx.log.add("start")
        return null
    }

    override fun stopClock(ctx: Ctx, effect: F.StopClock): A? {
        ctx.log.add("stop:${effect.reason}")
        return null
    }
}
