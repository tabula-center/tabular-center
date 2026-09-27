// Tests for `../src/TrafficLight.kt`, compiled as their own unit against the
// example's output rather than alongside it -- the Kotlin equivalent of a
// `tests/` directory. A test in the same unit can reach anything, so it
// never shows that the example's own surface is usable.

import dev.tabularcenter.Step
import examples.trafficlight.*

fun main() {
    run {
        val ctx = Ctx()
        val c = Controller()
        var s: S = S.Red
        repeat(6) {
            val outcome = step(c, ctx, s, A.Advance)
            s = (outcome as Step.Go).next
        }
        Check.eq(s, S.Red, "traffic light: two full cycles return to red")
        Check.eq(ctx.cycles, 2, "traffic light: context counted both cycles")
    }

    for (from in listOf(S.Red, S.Green, S.Amber)) {
        val outcome = step(Controller(), Ctx(), from, A.Fault)
        Check.eq(outcome, Step.Go(S.Red), "traffic light: fault from $from goes red")
    }

val cov = TABLE.coverage()
    Check.eq(cov.total, 6, "traffic light: six cells")
    Check.eq(cov.requiredMembers, 1, "traffic light: one implementation")

    Check.report("kotlin traffic light")
}
