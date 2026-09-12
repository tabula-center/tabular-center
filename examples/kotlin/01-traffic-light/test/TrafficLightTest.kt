// Tests for `../src/TrafficLight.kt`, compiled as their own unit against the example's
// output rather than alongside it -- the Kotlin equivalent of a `tests/`
// directory. An example is read as a template, and a template should not show
// its tests living inside the implementation.

import dev.tabula.Step

fun main() {
    run {
        val ctx = examples.trafficlight.Ctx()
        val c = examples.trafficlight.Controller()
        var s: examples.trafficlight.S = examples.trafficlight.S.Red
        repeat(6) {
            val step = examples.trafficlight.step(c, ctx, s, examples.trafficlight.A.Advance)
            s = (step as Step.Go).next
        }
        Check.eq(s, examples.trafficlight.S.Red, "traffic light: two full cycles return to red")
        Check.eq(ctx.cycles, 2, "traffic light: context counted both cycles")
    }

    for (from in listOf(examples.trafficlight.S.Red, examples.trafficlight.S.Green, examples.trafficlight.S.Amber)) {
        val step = examples.trafficlight.step(
            examples.trafficlight.Controller(), examples.trafficlight.Ctx(), from, examples.trafficlight.A.Fault,
        )
        Check.eq(step, Step.Go(examples.trafficlight.S.Red), "traffic light: fault from $from goes red")
    }

    val cov = examples.trafficlight.TABLE.coverage()
    Check.eq(cov.total, 6, "traffic light: six cells")
    Check.eq(cov.requiredMembers, 1, "traffic light: one implementation")

    Check.report("kotlin traffic light")
}
