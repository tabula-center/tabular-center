// Tests for `../src/Timer.kt`, compiled as their own unit against the
// example's output rather than alongside it -- the Kotlin equivalent of a
// `tests/` directory. A test in the same unit can reach anything, so it
// never shows that the example's own surface is usable.

import center.tabula.Step
import examples.timer.*

fun main() {
    val m = Impl()

    Check.eq(
        step(m, Ctx(10), S.Running(0), A.Tick(1)),
        Step.Stay<F>(),
        "timer: a tick below the limit stays",
    )
    Check.ok(
        step(m, Ctx(10), S.Running(0), A.Tick(1)) !is Step.Ignored,
        "timer: a tick while running is meaningful, not ignored",
    )
    Check.eq(
        step(m, Ctx(3), S.Running(2), A.Tick(9)),
        Step.Go(S.Done, listOf(F.StopClock(Reason.Elapsed))),
        "timer: the limit finishes the timer",
    )
    Check.eq(
        step(m, Ctx(100), S.Running(0), A.Cancel).effects,
        listOf(F.StopClock(Reason.Cancelled)),
        "timer: cancelling stops the clock for a different reason",
    )

    val ctx = Ctx(1)
    perform(m, ctx, F.StopClock(Reason.Elapsed))
    Check.eq(ctx.log, listOf("stop:Elapsed"), "timer: effect handlers receive narrowed payloads")

    for (pair in listOf(
        S.Idle to A.Tick(1),
        S.Idle to A.Cancel,
        S.Done to A.Cancel,
    )) {
        Check.ok(
            step(m, Ctx(1), pair.first, pair.second) is Step.Ignored,
            "timer: ${pair.second} means nothing in ${pair.first}",
        )
    }

    Check.report("kotlin timer")
}
