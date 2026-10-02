/**
 * **The KSP processor's specification.**
 *
 * Hand-written, exactly as `reference_timer.rs` was for the Rust macro: the
 * generator needs a target before it needs an implementation. Everything below
 * the "generated" line is what KSP must emit; everything above and below the
 * "developer" line is what a person writes.
 *
 * The matrix being specified:
 *
 * ```
 *               Start                   Tick     Cancel
 *   Idle    [   HANDLE,                 IGNORE,  IGNORE              ]
 *   Running [   IGNORE,                 HANDLE,  GO(Idle, StopClock) ]
 *   Done    [   GO(Running, StartClock) IGNORE,  IGNORE              ]
 * ```
 */
package reference

import center.tabula.*

// ---------------------------------------------------------------------------
// What the developer declares
// ---------------------------------------------------------------------------

sealed interface S {
    data object Idle : S
    data class Running(val since: Long) : S
    data object Done : S
}

sealed interface A {
    data object Start : A
    data class Tick(val now: Long) : A
    data object Cancel : A
}

sealed interface F {
    data object StartClock : F
    data class StopClock(val reason: Int) : F
}

/** Cross-state data. Rule R4: payload is state-local, Ctx outlives transitions. */
class Ctx(val limit: Long) {
    var ticksSeen = 0
    var lastStopReason: Int? = null
}

// The matrix itself lives in `TimerSpec.tb.kt`, next to this file.
//
// `spec/matrix-files.md` makes the case: a matrix is column-aligned on purpose
// and a general-purpose formatter's whole job is to normalise whitespace, so
// the two cannot share a file. `.editorconfig` exempts `*.tb.kt` and nothing
// else, and while the declaration sat here it was outside that exemption --
// unnoticed, because `kotlin-matrix-stable` had never run anywhere.

// ===========================================================================
// GENERATED — everything below this line is what KSP must emit
// ===========================================================================

/**
 * The cell surface: one required member per non-static cell, with NARROWED
 * argument types. The prototype's `suspend` is copied onto each.
 *
 * Static cells (IGNORE, GO) appear nowhere — they are resolved in the
 * dispatcher. Six of this machine's nine cells are static, which is what keeps
 * an N x M matrix survivable.
 *
 * An **interface**, not abstract members on the class, because this is what
 * composes: a parent machine that delegates here declares
 * `interface Cells : TimerCells`, and a hole anywhere in this surface then
 * breaks the *parent's* build. Interfaces are Kotlin's trait bounds. See
 * `Composition.kt`.
 */
interface TimerCells {
    suspend fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start): Step<S, F>
    suspend fun runningTick(ctx: Ctx, state: S.Running, action: A.Tick): Step<S, F>

    // One required member per effect variant, again with narrowed payloads.
    // Add an effect to the declaration and every handler stops compiling.
    suspend fun startClock(ctx: Ctx, effect: F.StartClock): A?
    suspend fun stopClock(ctx: Ctx, effect: F.StopClock): A?
}

/**
 * Convenience base class. The surface is [TimerCells]; this adds the
 * dispatcher as a method so a developer writes `class Timer : TimerMachine()`
 * rather than threading `this` through a free function.
 */
abstract class TimerMachine : TimerCells {

    /**
     * The dispatcher, which exists **only here**.
     *
     * A developer never writes a `when`, so `else` is not a temptation — it is
     * not available. That is the difference between a convention and a
     * guarantee, and it is why the matrix lives in annotations: KSP can only
     * generate new files, so the only way to own the dispatch is to be the
     * sole author of it.
     */
    suspend fun step(ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
        is S.Idle -> when (a) {
            is A.Start -> idleStart(ctx, s, a)
            is A.Tick -> Step.Ignored
            is A.Cancel -> Step.Ignored
        }
        is S.Running -> when (a) {
            is A.Start -> Step.Ignored
            is A.Tick -> runningTick(ctx, s, a) // smart-cast to S.Running
            is A.Cancel -> Step.Go(S.Idle, listOf(F.StopClock(1)))
        }
        is S.Done -> when (a) {
            is A.Start -> Step.Go(S.Running(0), listOf(F.StartClock))
            is A.Tick -> Step.Ignored
            is A.Cancel -> Step.Ignored
        }
    }

    /** Effect dispatch. Also no `else`. */
    suspend fun perform(ctx: Ctx, f: F): A? = when (f) {
        is F.StartClock -> startClock(ctx, f)
        is F.StopClock -> stopClock(ctx, f)
    }

    companion object {
        val TABLE = Table(
            machine = "Timer",
            states = listOf("Idle", "Running", "Done"),
            actions = listOf("Start", "Tick", "Cancel"),
            initial = "Idle",
            cells = listOf(
                listOf(Cell.Handle, Cell.Ignore, Cell.Ignore),
                listOf(Cell.Ignore, Cell.Handle, Cell.Go("Idle", listOf("StopClock"))),
                listOf(Cell.Go("Running", listOf("StartClock")), Cell.Ignore, Cell.Ignore),
            ),
        )
    }
}

// ===========================================================================
// DEVELOPER — two HANDLE cells, two effect variants, four overrides
// ===========================================================================

class Timer : TimerMachine() {
    override suspend fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start): Step<S, F> =
        Step.Go(S.Running(0), listOf(F.StartClock))

    override suspend fun runningTick(ctx: Ctx, state: S.Running, action: A.Tick): Step<S, F> {
        // Payload arrives destructured and non-optional: no `is`, no cast,
        // no `?:`. Rule R2.
        ctx.ticksSeen++
        return if (action.now - state.since >= ctx.limit) {
            Step.Go(S.Done, listOf(F.StopClock(2)))
        } else {
            Step.Stay()
        }
    }

    override suspend fun startClock(ctx: Ctx, effect: F.StartClock): A? = null

    override suspend fun stopClock(ctx: Ctx, effect: F.StopClock): A? {
        ctx.lastStopReason = effect.reason
        return null
    }
}
