// Tests for `../src/Suspend.kt`, compiled as their own unit against the
// example's output rather than alongside it.

import center.tabula.Step
import examples.suspending.*

fun main() {
    runSuspend {
        val (state, ctx) = run()
        Check.eq(state, S.Loaded, "suspend: one dispatch drives the machine to Loaded")
        Check.eq(
            ctx.log,
            listOf("fetch", "loaded"),
            "suspend: the follow-up action came back through the mailbox",
        )
    }

    runSuspend {
        val s = step(
            Impl(),
            Ctx(),
            S.Loading,
            A.Give,
        )
        Check.eq(s, Step.Go(S.Loaded), "suspend: GO needs no handler, colored or not")

        val ignored = step(
            Impl(),
            Ctx(),
            S.Loaded,
            A.Start,
        )
        Check.ok(ignored is Step.Ignored, "suspend: Start means nothing once Loaded")
    }

    val cov = TABLE.coverage()
    Check.eq(cov.total, 9, "suspend: nine cells")
    Check.eq(cov.requiredMembers, 2, "suspend: two implementations, both suspending")

    Check.report("kotlin suspend")
}
