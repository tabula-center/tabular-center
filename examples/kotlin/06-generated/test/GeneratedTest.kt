// Tests for the generated dispatcher, compiled against it the way every other
// example's tests are compiled against their example.
//
// Ordinary behavioural checks, deliberately. Generated code should be
// indistinguishable from hand-written code at the call site, and the only way
// to show that is to call it the same way.

import dev.tabula.Step
import generated.turnstile.A
import generated.turnstile.Ctx
import generated.turnstile.F
import generated.turnstile.Impl
import generated.turnstile.S
import generated.turnstile.step

fun main() {
    val cells = Impl()
    val ctx = Ctx()

    // A static cell: no member generated behind it, and it carries its effect.
    Check.eq(
        step(cells, ctx, S.Locked, A.Coin),
        Step.Go(S.Unlocked, listOf(F.Click)),
        "generated: a coin unlocks and clicks",
    )

    // IGNORE is generated too, and is not a handler returning Stay.
    Check.ok(
        step(cells, ctx, S.Locked, A.Push) is Step.Ignored,
        "generated: pushing a locked turnstile is not applicable",
    )

    // The one HANDLE cell reaches the developer's code, which touches ctx --
    // the reason it could not have been a static cell.
    Check.eq(
        step(cells, ctx, S.Unlocked, A.Push),
        Step.Go(S.Locked),
        "generated: pushing through relocks",
    )
    Check.eq(ctx.admitted, 1, "generated: the handler ran and saw its context")

    Check.report("kotlin generated")
}
