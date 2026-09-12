// Tests for `../src/Suspend.kt`, compiled as their own unit against the
// example's output rather than alongside it.

import dev.tabula.Step

fun main() {
    examples.suspending.runSuspend {
        val (state, ctx) = examples.suspending.run()
        Check.eq(state, examples.suspending.S.Loaded, "suspend: one dispatch drives the machine to Loaded")
        // Fetch returned an Arrived, which the driver queued rather than
        // recursed into. Two steps, two effects, one follow-up -- the same
        // property the blocking example demonstrates, in the other color.
        Check.eq(
            ctx.log,
            listOf("fetch", "loaded"),
            "suspend: the follow-up action came back through the mailbox",
        )
    }

    // A colored machine is still a machine: the static cells resolve without
    // any handler, and `Ignored` still means the action does not apply here.
    examples.suspending.runSuspend {
        val s = examples.suspending.step(
            examples.suspending.Impl(),
            examples.suspending.Ctx(),
            examples.suspending.S.Loading,
            examples.suspending.A.Give,
        )
        Check.eq(s, Step.Go(examples.suspending.S.Loaded), "suspend: GO needs no handler, colored or not")

        val ignored = examples.suspending.step(
            examples.suspending.Impl(),
            examples.suspending.Ctx(),
            examples.suspending.S.Loaded,
            examples.suspending.A.Start,
        )
        Check.ok(ignored is Step.Ignored, "suspend: Start means nothing once Loaded")
    }

    val cov = examples.suspending.TABLE.coverage()
    Check.eq(cov.total, 9, "suspend: nine cells")
    Check.eq(cov.requiredMembers, 2, "suspend: two implementations, both suspending")

    Check.report("kotlin suspend")
}
