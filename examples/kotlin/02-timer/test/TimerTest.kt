// Tests for `../src/Timer.kt`, compiled as their own unit against the example's
// output rather than alongside it -- the Kotlin equivalent of a `tests/`
// directory. An example is read as a template, and a template should not show
// its tests living inside the implementation.

import dev.tabula.Step

fun main() {
    val m = examples.timer.Impl()

    Check.eq(
        examples.timer.step(m, examples.timer.Ctx(10), examples.timer.S.Running(0), examples.timer.A.Tick(1)),
        Step.Stay<examples.timer.F>(),
        "timer: a tick below the limit stays",
    )
    Check.ok(
        examples.timer.step(m, examples.timer.Ctx(10), examples.timer.S.Running(0), examples.timer.A.Tick(1)) !is Step.Ignored,
        "timer: a tick while running is meaningful, not ignored",
    )
    Check.eq(
        examples.timer.step(m, examples.timer.Ctx(3), examples.timer.S.Running(2), examples.timer.A.Tick(9)),
        Step.Go(examples.timer.S.Done, listOf(examples.timer.F.StopClock(examples.timer.Reason.Elapsed))),
        "timer: the limit finishes the timer",
    )
    // The same effect, a different reason. The payload is what tells them apart.
    Check.eq(
        examples.timer.step(m, examples.timer.Ctx(100), examples.timer.S.Running(0), examples.timer.A.Cancel).effects,
        listOf(examples.timer.F.StopClock(examples.timer.Reason.Cancelled)),
        "timer: cancelling stops the clock for a different reason",
    )

    val ctx = examples.timer.Ctx(1)
    examples.timer.perform(m, ctx, examples.timer.F.StopClock(examples.timer.Reason.Elapsed))
    Check.eq(ctx.log, listOf("stop:Elapsed"), "timer: effect handlers receive narrowed payloads")

    for (pair in listOf(
        examples.timer.S.Idle to examples.timer.A.Tick(1),
        examples.timer.S.Idle to examples.timer.A.Cancel,
        examples.timer.S.Done to examples.timer.A.Cancel,
    )) {
        Check.ok(
            examples.timer.step(m, examples.timer.Ctx(1), pair.first, pair.second) is Step.Ignored,
            "timer: ${pair.second} means nothing in ${pair.first}",
        )
    }

    Check.report("kotlin timer")
}
