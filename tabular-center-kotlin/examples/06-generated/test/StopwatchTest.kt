// The receiver-colored machine, called the way its color demands.
//
// `with(clock) { step(...) }` is the whole point: `step` is an extension on
// `Clock`, so without one in scope there is no `step` to call. That is the
// color doing what `suspend` does for Gate -- deciding who may dispatch.
//
// Compiled in the test source set, which Gradle associates with `main`, so
// the `internal` generated surface is visible here as it would be to any code
// in the same module.
import dev.tabula.Step
import generated.stopwatch.A
import generated.stopwatch.Clock
import generated.stopwatch.Ctx
import generated.stopwatch.F
import generated.stopwatch.S
import generated.stopwatch.StopwatchImpl
import generated.stopwatch.perform
import generated.stopwatch.step

private class FakeClock(var t: Long) : Clock {
    override fun now(): Long = t
}

fun main() {
    val clock = FakeClock(100)
    val cells = StopwatchImpl()
    val ctx = Ctx()

    Check.eq(
        with(clock) { step(cells, ctx, S.Idle, A.Start) },
        Step.Go(S.Running(100)),
        "stopwatch: Start reads the receiver's clock into the payload",
    )

    clock.t = 150
    Check.eq(
        with(clock) { step(cells, ctx, S.Running(100), A.Stop) },
        Step.Go(S.Idle, listOf(F.Beep)),
        "stopwatch: Stop returns to Idle and beeps",
    )
    Check.eq(ctx.lastElapsed, 50L, "stopwatch: the cell measured against the receiver")

    Check.eq(
        with(clock) { perform(cells, ctx, F.Beep) },
        null,
        "stopwatch: the effect handler asks for nothing further",
    )
    Check.eq(ctx.beeps, 1, "stopwatch: the effect handler ran, on the receiver")

    Check.ok(
        with(clock) { step(cells, ctx, S.Idle, A.Stop) } is Step.Ignored,
        "stopwatch: IGNORE needs no receiver work and is still Ignored",
    )

    Check.report("kotlin generated (extension receiver, internal)")
}
