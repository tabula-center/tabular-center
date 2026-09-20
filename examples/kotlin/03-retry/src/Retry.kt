/**
 * **3. The driver, and why `step` is non-reentrant.**
 *
 * The only example where an effect handler returns an action. The follow-up
 * goes onto the mailbox and is stepped on the next turn of the loop, rather
 * than recursing into `step` from inside a handler — which a handler is given
 * no way to do.
 */
package examples.retry

import dev.tabula.Driver
import dev.tabula.Step

sealed interface S {
    data object Ready : S
    data class Waiting(val attempt: Int) : S
    data object Exhausted : S
}

sealed interface A {
    data object Attempt : A
    data object Elapsed : A
    data object Abort : A
}

sealed interface F {
    data class Sleep(val ms: Long) : F
    data object GiveUp : F
}

class Ctx(val maxAttempts: Int) {
    /** Every effect the handler carried out, in order. */
    val performed = mutableListOf<String>()
}

interface Cells {
    fun readyAttempt(ctx: Ctx, state: S.Ready, action: A.Attempt): Step<S, F>
    fun waitingElapsed(ctx: Ctx, state: S.Waiting, action: A.Elapsed): Step<S, F>
    fun sleep(ctx: Ctx, effect: F.Sleep): A?
    fun giveUp(ctx: Ctx, effect: F.GiveUp): A?
}

fun step(cells: Cells, ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
    is S.Ready -> when (a) {
        is A.Attempt -> cells.readyAttempt(ctx, s, a)
        is A.Elapsed -> Step.Ignored
        is A.Abort -> Step.Go(S.Exhausted)
    }
    is S.Waiting -> when (a) {
        is A.Attempt -> Step.Ignored
        is A.Elapsed -> cells.waitingElapsed(ctx, s, a)
        is A.Abort -> Step.Go(S.Exhausted)
    }
    is S.Exhausted -> when (a) {
        is A.Attempt -> Step.Ignored
        is A.Elapsed -> Step.Ignored
        is A.Abort -> Step.Ignored
    }
}

fun perform(cells: Cells, ctx: Ctx, f: F): A? = when (f) {
    is F.Sleep -> cells.sleep(ctx, f)
    is F.GiveUp -> cells.giveUp(ctx, f)
}

class Impl : Cells {
    override fun readyAttempt(ctx: Ctx, state: S.Ready, action: A.Attempt) =
        Step.Go(S.Waiting(1), listOf(F.Sleep(100)))

    override fun waitingElapsed(ctx: Ctx, state: S.Waiting, action: A.Elapsed): Step<S, F> =
        if (state.attempt >= ctx.maxAttempts) {
            Step.Go(S.Exhausted, listOf(F.GiveUp))
        } else {
            val next = state.attempt + 1
            Step.Go(S.Waiting(next), listOf(F.Sleep(100L * next)))
        }

    /**
     * Sleeping is what produces the next `Elapsed`.
     *
     * Returned as data. The driver enqueues it; this function cannot reach
     * `step` even if it wanted to.
     */
    override fun sleep(ctx: Ctx, effect: F.Sleep): A? {
        ctx.performed.add("sleep:${effect.ms}")
        return A.Elapsed
    }

    override fun giveUp(ctx: Ctx, effect: F.GiveUp): A? {
        ctx.performed.add("give-up")
        return null
    }
}

/** Drive from `Ready` until nothing is pending. */
fun run(maxAttempts: Int): Pair<S, Ctx> {
    val ctx = Ctx(maxAttempts)
    val cells = Impl()
    val driver = Driver<S, A, F>(S.Ready)
    driver.dispatch(
        A.Attempt,
        step = { s, a -> step(cells, ctx, s, a) },
        perform = { f -> perform(cells, ctx, f) },
    )
    return driver.state to ctx
}
