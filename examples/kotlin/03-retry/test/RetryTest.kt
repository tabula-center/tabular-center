// Tests for `../src/Retry.kt`, compiled as their own unit against the example's
// output rather than alongside it -- the Kotlin equivalent of a `tests/`
// directory. An example is read as a template, and a template should not show
// its tests living inside the implementation.

import dev.tabula.Step

fun main() {
    val (state3, ctx3) = examples.retry.run(3)
    Check.eq(state3, examples.retry.S.Exhausted, "retry: backs off and gives up on its own")
    Check.eq(
        ctx3.performed,
        listOf("sleep:100", "sleep:200", "sleep:300", "give-up"),
        "retry: one dispatch, four effects, all follow-ups through the mailbox",
    )

    val (_, ctx4) = examples.retry.run(4)
    Check.eq(
        ctx4.performed,
        listOf("sleep:100", "sleep:200", "sleep:300", "sleep:400", "give-up"),
        "retry: backoff grows with the attempt",
    )

    val (state1, ctx1) = examples.retry.run(1)
    Check.eq(state1, examples.retry.S.Exhausted, "retry: a single attempt gives up immediately")
    Check.eq(ctx1.performed, listOf("sleep:100", "give-up"), "retry: no extra sleeps")

    val aborted = examples.retry.step(examples.retry.Impl(), examples.retry.Ctx(5), examples.retry.S.Waiting(2), examples.retry.A.Abort)
    Check.eq(aborted, Step.Go(examples.retry.S.Exhausted), "retry: abort is static and needs no handler")

    Check.report("kotlin retry")
}
