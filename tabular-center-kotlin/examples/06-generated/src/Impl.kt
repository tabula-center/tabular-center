/**
 * The one cell the developer implements, plus the effect handler.
 *
 * `Cells` does not exist in this directory -- it is generated. Compiling this
 * file is therefore the real test: if the emitter produced a surface that
 * cannot be satisfied, or named a member differently than a reader would
 * expect, this stops compiling.
 */
package generated.turnstile

import dev.tabula.Step

class Impl : Cells {
    /** The only cell with a decision in it: a static cell cannot touch `ctx`. */
    override fun unlockedPush(ctx: Ctx, state: S.Unlocked, action: A.Push): Step<S, F> {
        ctx.admitted += 1
        return Step.Go(S.Locked)
    }

    override fun click(ctx: Ctx, effect: F.Click): A? = null
}
