/**
 * **4. Composition.**
 *
 * A login session delegating its authentication to a child machine.
 *
 * `interface Cells : auth.Cells` is the composition property in one line:
 * implementing the parent requires implementing the child, so a hole anywhere
 * in the child breaks the parent's build. Interfaces are Kotlin's trait bounds.
 */
package examples.session

import dev.tabula.Cell
import dev.tabula.Step
import dev.tabula.Table

/** The child: authentication, written knowing nothing about sessions. */
object auth {
    sealed interface S {
        data class AwaitingCredentials(val attempts: Int) : S
        data object Authenticated : S
        data object LockedOut : S
    }
    sealed interface A {
        data class Submit(val ok: Boolean) : A
        data object Reset : A
    }
    sealed interface F {
        data object Prompt : F
        data object Lockout : F
    }

    class Ctx(val maxAttempts: Int)

    interface Cells {
        fun awaitingSubmit(ctx: Ctx, state: S.AwaitingCredentials, action: A.Submit): Step<S, F>
    }

    fun step(cells: Cells, ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
        is S.AwaitingCredentials -> when (a) {
            is A.Submit -> cells.awaitingSubmit(ctx, s, a)
            is A.Reset -> Step.Go(S.AwaitingCredentials(0), listOf(F.Prompt))
        }
        is S.Authenticated -> when (a) {
            is A.Submit -> Step.Ignored
            is A.Reset -> Step.Go(S.AwaitingCredentials(0), listOf(F.Prompt))
        }
        is S.LockedOut -> when (a) {
            is A.Submit -> Step.Ignored
            is A.Reset -> Step.Ignored
        }
    }

    val TABLE = Table(
        machine = "Auth",
        states = listOf("AwaitingCredentials", "Authenticated", "LockedOut"),
        actions = listOf("Submit", "Reset"),
        initial = "AwaitingCredentials",
        cells = listOf(
            listOf(Cell.Handle, Cell.Go("AwaitingCredentials", listOf("Prompt"))),
            listOf(Cell.Ignore, Cell.Go("AwaitingCredentials", listOf("Prompt"))),
            listOf(Cell.Ignore, Cell.Ignore),
        ),
    )
}

object session {
    sealed interface S {
        data class LoggedOut(val auth: examples.session.auth.S) : S
        data object Active : S
        data object Banned : S
    }
    sealed interface A {
        data class Credentials(val ok: Boolean) : A
        data object StartOver : A
        data object Logout : A
    }
    sealed interface F {
        data object Audit : F
        data object Warn : F
        data object Redirect : F
    }

    /** The parent's context contains the child's, so `authChildCtx` is a field. */
    class Ctx(val auth: examples.session.auth.Ctx)

    interface Cells : examples.session.auth.Cells {
        // One per DELEGATE cell: the action prism.
        fun loggedOutCredentialsToChild(
            ctx: Ctx,
            state: S.LoggedOut,
            action: A.Credentials,
        ): examples.session.auth.A?

        fun loggedOutStartOverToChild(
            ctx: Ctx,
            state: S.LoggedOut,
            action: A.StartOver,
        ): examples.session.auth.A?

        // Once per child: the lens, the effect relabelling, the context.
        fun authChildState(state: S.LoggedOut): examples.session.auth.S
        fun authEmbed(state: S.LoggedOut, child: examples.session.auth.S): S
        fun authLift(effect: examples.session.auth.F): F
        fun authChildCtx(ctx: Ctx): examples.session.auth.Ctx
    }

    fun step(cells: Cells, ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
        is S.LoggedOut -> when (a) {
            is A.Credentials -> delegate(cells, ctx, s, cells.loggedOutCredentialsToChild(ctx, s, a))
            is A.StartOver -> delegate(cells, ctx, s, cells.loggedOutStartOverToChild(ctx, s, a))
            is A.Logout -> Step.Ignored
        }
        is S.Active -> when (a) {
            is A.Credentials -> Step.Ignored
            is A.StartOver -> Step.Ignored
            is A.Logout -> Step.Go(S.Banned, listOf(F.Audit))
        }
        is S.Banned -> when (a) {
            is A.Credentials -> Step.Ignored
            is A.StartOver -> Step.Ignored
            is A.Logout -> Step.Ignored
        }
    }

    private fun delegate(
        cells: Cells,
        ctx: Ctx,
        state: S.LoggedOut,
        childAction: examples.session.auth.A?,
    ): Step<S, F> {
        // A null child action reports Ignored, not Stay: a parent action the
        // child's alphabet does not contain was not handled.
        if (childAction == null) return Step.Ignored
        val childStep = examples.session.auth.step(
            cells,
            cells.authChildCtx(ctx),
            cells.authChildState(state),
            childAction,
        )
        val effects = childStep.effects.map(cells::authLift)
        return when (childStep) {
            is Step.Go -> Step.Go(cells.authEmbed(state, childStep.next), effects)
            is Step.Stay -> Step.Stay(effects)
            is Step.Ignored -> Step.Ignored
        }
    }

    val TABLE = Table(
        machine = "Session",
        states = listOf("LoggedOut", "Active", "Banned"),
        actions = listOf("Credentials", "StartOver", "Logout"),
        initial = "LoggedOut",
        cells = listOf(
            listOf(Cell.Delegate("auth"), Cell.Delegate("auth"), Cell.Ignore),
            listOf(Cell.Ignore, Cell.Ignore, Cell.Go("Banned", listOf("Audit"))),
            listOf(Cell.Ignore, Cell.Ignore, Cell.Ignore),
        ),
    )
}

/** One object satisfying both machines' surfaces. */
class Impl : session.Cells {
    override fun awaitingSubmit(
        ctx: auth.Ctx,
        state: auth.S.AwaitingCredentials,
        action: auth.A.Submit,
    ): Step<auth.S, auth.F> = when {
        action.ok -> Step.Go(auth.S.Authenticated)
        state.attempts + 1 >= ctx.maxAttempts ->
            Step.Go(auth.S.LockedOut, listOf(auth.F.Lockout))
        else ->
            Step.Go(auth.S.AwaitingCredentials(state.attempts + 1), listOf(auth.F.Prompt))
    }

    override fun loggedOutCredentialsToChild(
        ctx: session.Ctx,
        state: session.S.LoggedOut,
        action: session.A.Credentials,
    ) = auth.A.Submit(action.ok)

    override fun loggedOutStartOverToChild(
        ctx: session.Ctx,
        state: session.S.LoggedOut,
        action: session.A.StartOver,
    ) = auth.A.Reset

    override fun authChildState(state: session.S.LoggedOut) = state.auth

    /** A child transition can be a parent transition. */
    override fun authEmbed(state: session.S.LoggedOut, child: auth.S): session.S = when (child) {
        is auth.S.Authenticated -> session.S.Active
        is auth.S.LockedOut -> session.S.Banned
        is auth.S.AwaitingCredentials -> session.S.LoggedOut(child)
    }

    override fun authLift(effect: auth.F): session.F = when (effect) {
        is auth.F.Prompt -> session.F.Redirect
        is auth.F.Lockout -> session.F.Warn
    }

    override fun authChildCtx(ctx: session.Ctx) = ctx.auth
}
