// Tests for `../src/Retry.kt`, compiled as their own unit against the
// example's output rather than alongside it -- the Kotlin equivalent of a
// `tests/` directory. A test in the same unit can reach anything, so it
// never shows that the example's own surface is usable.

import dev.tabularcenter.Step
import examples.retry.*

fun main() {
    val (state3, ctx3) = run(3)
    Check.eq(state3, S.Exhausted, "retry: backs off and gives up on its own")
    Check.eq(
        ctx3.performed,
        listOf("sleep:100", "sleep:200", "sleep:300", "give-up"),
        "retry: one dispatch, four effects, all follow-ups through the mailbox",
    )

    val (_, ctx4) = run(4)
    Check.eq(
        ctx4.performed,
        listOf("sleep:100", "sleep:200", "sleep:300", "sleep:400", "give-up"),
        "retry: backoff grows with the attempt",
    )

    val (state1, ctx1) = run(1)
    Check.eq(state1, S.Exhausted, "retry: a single attempt gives up immediately")
    Check.eq(ctx1.performed, listOf("sleep:100", "give-up"), "retry: no extra sleeps")

    val aborted = step(Impl(), Ctx(5), S.Waiting(2), A.Abort)
    Check.eq(aborted, Step.Go(S.Exhausted), "retry: abort is static and needs no handler")

    Check.report("kotlin retry")
}
