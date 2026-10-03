// Tests for the generated dispatcher, compiled against it the way every other
// example's tests are compiled against their example.
//
// Ordinary behavioural checks, deliberately. Generated code should be
// indistinguishable from hand-written code at the call site, and the only way
// to show that is to call it the same way.

import center.tabula.Step
import generated.turnstile.A
import generated.turnstile.Ctx
import generated.turnstile.F
import generated.turnstile.Impl
import generated.turnstile.S
import generated.turnstile.step

fun main() {
    val cells = Impl()
    val ctx = Ctx()

    Check.eq(
        step(cells, ctx, S.Locked, A.Coin),
        Step.Go(S.Unlocked, listOf(F.Click)),
        "generated: a coin unlocks and clicks",
    )

    Check.ok(
        step(cells, ctx, S.Locked, A.Push) is Step.Ignored,
        "generated: pushing a locked turnstile is not applicable",
    )

    Check.eq(
        step(cells, ctx, S.Unlocked, A.Push),
        Step.Go(S.Locked),
        "generated: pushing through relocks",
    )
    Check.eq(ctx.admitted, 1, "generated: the handler ran and saw its context")

    Check.report("kotlin generated")
}
