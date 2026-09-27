/**
 * **1. The minimum.**
 *
 * Three states, two actions, no payloads, no effects. Six cells, one of which
 * the developer writes.
 *
 * `Nothing` is Kotlin's uninhabited type, so `Step<S, Nothing>` is a machine
 * that cannot emit — the counterpart of Rust's `effects Effect { }`.
 */
package examples.trafficlight

import dev.tabularcenter.Step

sealed interface S {
    data object Red : S
    data object Green : S
    data object Amber : S
}

sealed interface A {
    data object Advance : A
    data object Fault : A
}

class Ctx(var cycles: Int = 0)

interface Cells {
    fun amberAdvance(ctx: Ctx, state: S.Amber, action: A.Advance): Step<S, Nothing>
}

fun step(cells: Cells, ctx: Ctx, s: S, a: A): Step<S, Nothing> = when (s) {
    is S.Red -> when (a) {
        is A.Advance -> Step.Go(S.Green)
        is A.Fault -> Step.Go(S.Red)
    }
    is S.Green -> when (a) {
        is A.Advance -> Step.Go(S.Amber)
        is A.Fault -> Step.Go(S.Red)
    }
    is S.Amber -> when (a) {
        is A.Advance -> cells.amberAdvance(ctx, s, a)
        is A.Fault -> Step.Go(S.Red)
    }
}

class Controller : Cells {
    /**
     * The one cell with a decision in it.
     *
     * It could have been `GO(Red)` — it is `HANDLE` because it touches
     * context, and a static cell cannot. That boundary is why both kinds
     * exist.
     */
    override fun amberAdvance(ctx: Ctx, state: S.Amber, action: A.Advance): Step<S, Nothing> {
        ctx.cycles++
        return Step.Go(S.Red)
    }
}
