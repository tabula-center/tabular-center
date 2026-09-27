/**
 * Composition: a parent machine driving a child through a `DELEGATE` cell.
 *
 * The claim under test, the same one `composition.rs` proves for Rust:
 *
 * > Scoping a total child into a total parent yields a total parent, and the
 * > compiler proves it by the same mechanism as everything else.
 *
 * **Interfaces are Kotlin's trait bounds.** The parent's surface *extends* the
 * child's (`interface Cells : retry.Cells`), so a hole anywhere in the child
 * breaks any class implementing the parent:
 *
 * ```
 * error: class 'Impl' is not abstract and does not implement abstract member:
 * fun waitingElapsed(ctx: Ctx, state: S.Waiting, action: A.Elapsed): Step<S, F>
 * ```
 *
 * A hand-written `HANDLE` body could never give that — it is free to ignore
 * the child, so no requirement would propagate.
 */
package composition

import dev.tabularcenter.*

// ---------------------------------------------------------------------------
// Child: a retry machine, written without knowing anything about its parent.
// ---------------------------------------------------------------------------

object retry {
    sealed interface S {
        data object Ready : S
        data class Waiting(val attempt: Long) : S
        data object Exhausted : S
    }
    sealed interface A {
        data object Attempt : A
        data object Elapsed : A
        data object Abort : A
    }
    sealed interface F {
        data object Sleep : F
        data object GiveUp : F
    }

    class Ctx(val maxAttempts: Long)

    /** The composable surface. */
    interface Cells {
        fun readyAttempt(ctx: Ctx, state: S.Ready, action: A.Attempt): Step<S, F>
        fun waitingElapsed(ctx: Ctx, state: S.Waiting, action: A.Elapsed): Step<S, F>
    }

    /**
     * Dispatch, taking the surface rather than being a method on it.
     *
     * Free function so a parent can pass its own `this` — one object satisfying
     * both machines' surfaces, exactly as the Rust `Impl` implements both
     * machines' `Handle` bounds.
     */
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

    val TABLE = Table(
        machine = "Retry",
        states = listOf("Ready", "Waiting", "Exhausted"),
        actions = listOf("Attempt", "Elapsed", "Abort"),
        initial = "Ready",
        cells = listOf(
            listOf(Cell.Handle, Cell.Ignore, Cell.Go("Exhausted")),
            listOf(Cell.Ignore, Cell.Handle, Cell.Go("Exhausted")),
            listOf(Cell.Ignore, Cell.Ignore, Cell.Ignore),
        ),
    )
}

// ---------------------------------------------------------------------------
// Parent: a job machine whose Retrying state holds the child's state.
// ---------------------------------------------------------------------------

object job {
    sealed interface S {
        data object Idle : S
        data class Retrying(val child: retry.S) : S
        data object Done : S
    }
    sealed interface A {
        data object Run : A
        data object Tick : A
        data object Cancel : A
    }
    sealed interface F {
        data object Log : F
        data object Backoff : F
        data object Alert : F
    }

    /** The parent context **contains** the child's, so `childCtx` is a field. */
    class Ctx(val retry: composition.retry.Ctx)

    /**
     * The parent's surface **extends the child's**.
     *
     * This is the composition property in one line: implementing `job.Cells`
     * requires implementing `retry.Cells` too, so a hole in the child breaks
     * the parent's build. Interfaces are Kotlin's trait bounds.
     *
     * ## Why the delegate members are named rather than generic
     *
     * Rust expresses a `DELEGATE` cell as `Delegate<M, SV, AV, CM>`, one trait
     * implemented at several type arguments. **Kotlin cannot do that**: a class
     * may implement a generic interface at only one argument, so
     * `Cells : Delegate<A.Run>, Delegate<A.Tick>` is
     * `type parameter 'AV' has inconsistent values`.
     *
     * So the generator emits one named member per delegate cell instead —
     * which is the form it should have used regardless. Rust reaches for a
     * generic trait only because `macro_rules!` cannot concatenate
     * identifiers; KSP can. Same divergence as the cell surface itself
     * (ARCHITECTURE 11.0), arriving for the same reason.
     *
     * The four lens members are per *child*, not per cell: a second delegate
     * cell to the same child reuses them. Nest, alternate, and translate are
     * not three APIs — they are these members. `retryChildState` + `retryEmbed`
     * are the lens, `...ToChild` is the action prism, `retryLift` relabels
     * effects, `retryChildCtx` plumbs context. Each encodes a decision that
     * cannot be derived, which is why none is generated.
     */
    interface Cells : retry.Cells {
        fun idleRun(ctx: Ctx, state: S.Idle, action: A.Run): Step<S, F>

        // One per DELEGATE cell: the action prism.
        fun retryingRunToChild(ctx: Ctx, state: S.Retrying, action: A.Run): retry.A?
        fun retryingTickToChild(ctx: Ctx, state: S.Retrying, action: A.Tick): retry.A?

        // Once per child: the lens, the effect relabelling, the context.
        fun retryChildState(state: S.Retrying): retry.S
        fun retryEmbed(state: S.Retrying, child: retry.S): S
        fun retryLift(effect: retry.F): F
        fun retryChildCtx(ctx: Ctx): retry.Ctx
    }

    fun step(cells: Cells, ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
        is S.Idle -> when (a) {
            is A.Run -> cells.idleRun(ctx, s, a)
            is A.Tick -> Step.Ignored
            is A.Cancel -> Step.Ignored
        }
        is S.Retrying -> when (a) {
            is A.Run -> delegate(cells, ctx, s, cells.retryingRunToChild(ctx, s, a))
            is A.Tick -> delegate(cells, ctx, s, cells.retryingTickToChild(ctx, s, a))
            is A.Cancel -> Step.Go(S.Done, listOf(F.Log))
        }
        is S.Done -> when (a) {
            is A.Run -> Step.Ignored
            is A.Tick -> Step.Ignored
            is A.Cancel -> Step.Ignored
        }
    }

    /**
     * Run the child and fold the result back.
     *
     * `toChild` returning null reports **Ignored**, not Stay: a parent action
     * the child's alphabet does not contain was not handled, and the
     * distinction is load-bearing for the lints.
     */
    private fun delegate(
        cells: Cells,
        ctx: Ctx,
        state: S.Retrying,
        childAction: retry.A?,
    ): Step<S, F> {
        if (childAction == null) return Step.Ignored
        val childStep = retry.step(
            cells,
            cells.retryChildCtx(ctx),
            cells.retryChildState(state),
            childAction,
        )
        val effects = childStep.effects.map(cells::retryLift)
        return when (childStep) {
            is Step.Go -> Step.Go(cells.retryEmbed(state, childStep.next), effects)
            is Step.Stay -> Step.Stay(effects)
            is Step.Ignored -> Step.Ignored
        }
    }

    val TABLE = Table(
        machine = "Job",
        states = listOf("Idle", "Retrying", "Done"),
        actions = listOf("Run", "Tick", "Cancel"),
        initial = "Idle",
        cells = listOf(
            listOf(Cell.Handle, Cell.Ignore, Cell.Ignore),
            listOf(Cell.Delegate("retry"), Cell.Delegate("retry"), Cell.Go("Done", listOf("Log"))),
            listOf(Cell.Ignore, Cell.Ignore, Cell.Ignore),
        ),
    )
}

// ---------------------------------------------------------------------------
// The developer's side: one object satisfying BOTH machines' surfaces.
// ---------------------------------------------------------------------------

class Impl : job.Cells {
    // The parent's own HANDLE cell.
    override fun idleRun(ctx: job.Ctx, state: job.S.Idle, action: job.A.Run) =
        Step.Go(job.S.Retrying(retry.S.Ready), listOf(job.F.Log))

    // The CHILD's cells, required because `job.Cells : retry.Cells`.
    override fun readyAttempt(ctx: retry.Ctx, state: retry.S.Ready, action: retry.A.Attempt) =
        Step.Go(retry.S.Waiting(1), listOf(retry.F.Sleep))

    override fun waitingElapsed(
        ctx: retry.Ctx,
        state: retry.S.Waiting,
        action: retry.A.Elapsed,
    ): Step<retry.S, retry.F> =
        if (state.attempt >= ctx.maxAttempts) {
            Step.Go(retry.S.Exhausted, listOf(retry.F.GiveUp))
        } else {
            Step.Go(retry.S.Waiting(state.attempt + 1), listOf(retry.F.Sleep))
        }

    // The delegate cells.
    override fun retryingRunToChild(ctx: job.Ctx, state: job.S.Retrying, action: job.A.Run) =
        retry.A.Attempt

    override fun retryingTickToChild(ctx: job.Ctx, state: job.S.Retrying, action: job.A.Tick) =
        retry.A.Elapsed

    override fun retryChildState(state: job.S.Retrying) = state.child

    /**
     * A child transition can be a parent transition.
     *
     * `embed` returns the full parent state, not the narrowed variant, because
     * a child reaching its terminal state is usually the parent's cue to leave.
     */
    override fun retryEmbed(state: job.S.Retrying, child: retry.S): job.S =
        if (child is retry.S.Exhausted) job.S.Done else job.S.Retrying(child)

    override fun retryLift(effect: retry.F): job.F = when (effect) {
        is retry.F.Sleep -> job.F.Backoff
        is retry.F.GiveUp -> job.F.Alert
    }

    override fun retryChildCtx(ctx: job.Ctx) = ctx.retry
}
