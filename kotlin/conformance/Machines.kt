package conformance

import dev.tabula.*
import dev.tabula.testing.*

/**
 * The fixture machines, written in the shape KSP will generate.
 *
 * Each is the Kotlin counterpart of a Rust adapter in `tabula-conformance`.
 * The two implementations agreeing on these fixtures is the only thing keeping
 * them from drifting.
 */

/** Binds one fixture to one real machine. */
interface Adapter {
    /** Fixture name; `<name>.tbl` and `traces/<name>.trace`. */
    val name: String

    /** The generated table. */
    val table: Table

    /**
     * Payload fields, as `(state, field, type)`.
     *
     * Separate from [table] because only the lints need it, and only
     * `tabula::payload-hoist` among those. Rust has passed its `PAYLOADS` to
     * the lint since the lint existed; this side was calling `report(table)`
     * and taking the empty default, so the two agreed only because no fixture
     * had a field repeated often enough to fire.
     *
     * `type` is spelled in the implementation's own language. See
     * `spec/diagnostics.md`.
     */
    val payloads: Payloads get() = emptyList()

    /** Replay one trace, one [Observed] per step. */
    fun replay(trace: Trace): List<Observed>
}

/** Outcome of one replayed step, in fixture vocabulary. */
data class Observed(val expect: Expect, val effects: List<String>)

// ---------------------------------------------------------------------------
// timer.tbl
// ---------------------------------------------------------------------------

object timer {
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
        data object StopClock : F
    }
    class Ctx(val limit: Long)

    abstract class Machine {
        abstract fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start): Step<S, F>
        abstract fun runningTick(ctx: Ctx, state: S.Running, action: A.Tick): Step<S, F>

        fun step(ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
            is S.Idle -> when (a) {
                is A.Start -> idleStart(ctx, s, a)
                is A.Tick -> Step.Ignored
                is A.Cancel -> Step.Ignored
            }
            is S.Running -> when (a) {
                is A.Start -> Step.Ignored
                is A.Tick -> runningTick(ctx, s, a)
                is A.Cancel -> Step.Go(S.Idle, listOf(F.StopClock))
            }
            is S.Done -> when (a) {
                is A.Start -> Step.Go(S.Running(0), listOf(F.StartClock))
                is A.Tick -> Step.Ignored
                is A.Cancel -> Step.Ignored
            }
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

    class Impl : Machine() {
        override fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start) =
            Step.Go(S.Running(0), listOf(F.StartClock))

        override fun runningTick(ctx: Ctx, state: S.Running, action: A.Tick): Step<S, F> =
            if (action.now - state.since >= ctx.limit) Step.Go(S.Done, listOf(F.StopClock))
            else Step.Stay()
    }
}

object TimerAdapter : Adapter {
    override val name = "timer"
    override val payloads: Payloads = listOf(Triple("Running", "since", "Long"))
    override val table = timer.Machine.TABLE

    override fun replay(trace: Trace): List<Observed> {
        val ctx = timer.Ctx(trace.ctx["limit"] ?: 0)
        val m = timer.Impl()
        var state: timer.S = stateOf(trace.from, trace.fromFields)
        return trace.steps.map { st ->
            val step = m.step(ctx, state, actionOf(st.action, st.args))
            val effects = step.effects.map { it.toString() }
            val expect = when (step) {
                is Step.Stay -> Expect.Stay
                is Step.Ignored -> Expect.Ignored
                is Step.Go -> {
                    state = step.next
                    val want = (st.expect as? Expect.Go)?.fields ?: emptyMap()
                    describe(step.next, want)
                }
            }
            Observed(expect, effects)
        }
    }

    private fun stateOf(name: String, f: Map<String, Long>): timer.S = when (name) {
        "Idle" -> timer.S.Idle
        "Done" -> timer.S.Done
        "Running" -> timer.S.Running(f["since"] ?: 0)
        else -> error("timer: unknown state `$name`")
    }

    private fun actionOf(name: String, a: Map<String, Long>): timer.A = when (name) {
        "Start" -> timer.A.Start
        "Cancel" -> timer.A.Cancel
        "Tick" -> timer.A.Tick(a["now"] ?: 0)
        else -> error("timer: unknown action `$name`")
    }

    private fun describe(s: timer.S, want: Map<String, Long>): Expect.Go = when (s) {
        is timer.S.Idle -> Expect.Go("Idle", emptyMap())
        is timer.S.Done -> Expect.Go("Done", emptyMap())
        is timer.S.Running ->
            Expect.Go("Running", if (want.containsKey("since")) mapOf("since" to s.since) else emptyMap())
    }
}

// ---------------------------------------------------------------------------
// toggle.tbl -- the only coverage for EMIT and UNREACHABLE
// ---------------------------------------------------------------------------

object toggle {
    sealed interface S {
        data object Off : S
        data object On : S
    }
    sealed interface A {
        data object Flip : A
        data object Poke : A
        data object Reset : A
    }
    sealed interface F {
        data object Light : F
        data object Buzz : F
    }
    object Ctx

    abstract class Machine {
        abstract fun onPoke(ctx: Ctx, state: S.On, action: A.Poke): Step<S, F>

        fun step(ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
            is S.Off -> when (a) {
                is A.Flip -> Step.Go(S.On, listOf(F.Light))
                is A.Poke -> Step.Stay(listOf(F.Buzz))
                is A.Reset -> Step.Ignored
            }
            is S.On -> when (a) {
                is A.Flip -> Step.Go(S.Off)
                is A.Poke -> onPoke(ctx, s, a)
                // UNREACHABLE compiles to a trap. Writing it *is* the
                // implementation, so it generates no member.
                is A.Reset -> error("tabula: On x Reset was declared UNREACHABLE but occurred")
            }
        }

        companion object {
            val TABLE = Table(
                machine = "Toggle",
                states = listOf("Off", "On"),
                actions = listOf("Flip", "Poke", "Reset"),
                initial = "Off",
                cells = listOf(
                    listOf(Cell.Go("On", listOf("Light")), Cell.Emit(listOf("Buzz")), Cell.Ignore),
                    listOf(Cell.Go("Off"), Cell.Handle, Cell.Unreachable),
                ),
            )
        }
    }

    class Impl : Machine() {
        override fun onPoke(ctx: Ctx, state: S.On, action: A.Poke): Step<S, F> = Step.Stay()
    }
}

/**
 * A machine with an uninhabited effect enum.
 *
 * `sealed interface F` with no implementors is Kotlin's `effects F { }`. What
 * makes it worth a fixture is what it removes: with no effect to name, `EMIT`
 * cannot be written at all, because an empty one is `tabula::empty-emit`.
 *
 * `Open` is reached only from the `HANDLE` cell at `(Locked, Unlock)`, which
 * is why the coverage report must stay silent about its lack of a static
 * incoming transition.
 */
object effectsNever {
    sealed interface S {
        data object Locked : S
        data object Open : S
    }
    sealed interface A {
        data object Unlock : A
        data object Lock : A
        data object Push : A
    }

    /** No implementors: nothing can ever construct one. */
    sealed interface F

    object Ctx

    abstract class Machine {
        abstract fun onUnlock(ctx: Ctx, state: S.Locked, action: A.Unlock): Step<S, F>
        abstract fun onPush(ctx: Ctx, state: S.Open, action: A.Push): Step<S, F>

        fun step(ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
            is S.Locked -> when (a) {
                is A.Unlock -> onUnlock(ctx, s, a)
                is A.Lock -> Step.Ignored
                is A.Push -> Step.Ignored
            }
            is S.Open -> when (a) {
                is A.Unlock -> Step.Ignored
                is A.Lock -> Step.Go(S.Locked)
                is A.Push -> onPush(ctx, s, a)
            }
        }

        companion object {
            val TABLE = Table(
                machine = "Gate",
                states = listOf("Locked", "Open"),
                actions = listOf("Unlock", "Lock", "Push"),
                initial = "Locked",
                cells = listOf(
                    listOf(Cell.Handle, Cell.Ignore, Cell.Ignore),
                    listOf(Cell.Ignore, Cell.Go("Locked"), Cell.Handle),
                ),
            )
        }
    }

    class Impl : Machine() {
        // The only route into Open, and deliberately dynamic: a statically
        // resolvable transition here would make the matrix fully static and
        // defeat the reachability gate this fixture pins.
        override fun onUnlock(ctx: Ctx, state: S.Locked, action: A.Unlock): Step<S, F> =
            Step.Go(S.Open)

        override fun onPush(ctx: Ctx, state: S.Open, action: A.Push): Step<S, F> = Step.Stay()
    }
}

object EffectsNeverAdapter : Adapter {
    override val name = "effects-never"
    override val table = effectsNever.Machine.TABLE

    override fun replay(trace: Trace): List<Observed> {
        val m = effectsNever.Impl()
        var state: effectsNever.S = when (trace.from) {
            "Locked" -> effectsNever.S.Locked
            "Open" -> effectsNever.S.Open
            else -> error("effects-never: unknown state `${trace.from}`")
        }
        return trace.steps.map { st ->
            val action = when (st.action) {
                "Unlock" -> effectsNever.A.Unlock
                "Lock" -> effectsNever.A.Lock
                "Push" -> effectsNever.A.Push
                else -> error("effects-never: unknown action `${st.action}`")
            }
            val step = m.step(effectsNever.Ctx, state, action)
            // Always empty -- F has no implementors -- but mapped the same way
            // as every other adapter, so the trace assertions test the real
            // path rather than a short circuit.
            val effects = step.effects.map { it.toString() }
            val expect = when (step) {
                is Step.Stay -> Expect.Stay
                is Step.Ignored -> Expect.Ignored
                is Step.Go -> {
                    state = step.next
                    val n = if (step.next is effectsNever.S.Locked) "Locked" else "Open"
                    Expect.Go(n, emptyMap())
                }
            }
            Observed(expect, effects)
        }
    }
}

object ToggleAdapter : Adapter {
    override val name = "toggle"
    override val table = toggle.Machine.TABLE

    override fun replay(trace: Trace): List<Observed> {
        val m = toggle.Impl()
        var state: toggle.S = when (trace.from) {
            "Off" -> toggle.S.Off
            "On" -> toggle.S.On
            else -> error("toggle: unknown state `${trace.from}`")
        }
        return trace.steps.map { st ->
            val action = when (st.action) {
                "Flip" -> toggle.A.Flip
                "Poke" -> toggle.A.Poke
                "Reset" -> toggle.A.Reset
                else -> error("toggle: unknown action `${st.action}`")
            }
            val step = m.step(toggle.Ctx, state, action)
            val effects = step.effects.map { it.toString() }
            val expect = when (step) {
                is Step.Stay -> Expect.Stay
                is Step.Ignored -> Expect.Ignored
                is Step.Go -> {
                    state = step.next
                    Expect.Go(if (step.next is toggle.S.Off) "Off" else "On", emptyMap())
                }
            }
            Observed(expect, effects)
        }
    }
}

// ---------------------------------------------------------------------------
// payload-hoist.tbl -- the only coverage for `tabula::payload-hoist`
// ---------------------------------------------------------------------------

/**
 * `attempt` in three states, which is what the lint is looking for.
 *
 * The machine is deliberately a little wrong: a retry counter that outlives
 * every transition belongs in Context, and three states carrying their own
 * copy is the smell `tabula::payload-hoist` names. The fixture models the
 * smell rather than the fix, because a fixture for a lint has to trip it.
 *
 * `F` has no variants. A machine with no effects is legal and this is the only
 * fixture that exercises it -- `Step<S, F>` still type-checks, `effects` is
 * always empty, and the coverage report says `emit 0`.
 */
object payloadHoist {
    sealed interface S {
        data class Connecting(val attempt: Long) : S
        data class Backoff(val attempt: Long) : S
        data class Reconnecting(val attempt: Long) : S
        data object Live : S
    }
    sealed interface A {
        data object Open : A
        data object Fail : A
        data object Timeout : A
    }
    sealed interface F

    class Ctx(val maxAttempts: Long)

    abstract class Machine {
        abstract fun connectingOpen(ctx: Ctx, state: S.Connecting, action: A.Open): Step<S, F>
        abstract fun backoffTimeout(ctx: Ctx, state: S.Backoff, action: A.Timeout): Step<S, F>
        abstract fun reconnectingOpen(ctx: Ctx, state: S.Reconnecting, action: A.Open): Step<S, F>

        fun step(ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
            is S.Connecting -> when (a) {
                is A.Open -> connectingOpen(ctx, s, a)
                // A static cell cannot read the state it is leaving, so the
                // counter restarts here. That is not a shortcut for the
                // fixture -- it is what GO means, and it is half of why this
                // machine wants the field hoisted.
                is A.Fail -> Step.Go(S.Backoff(0))
                is A.Timeout -> Step.Go(S.Backoff(0))
            }
            is S.Backoff -> when (a) {
                is A.Open -> Step.Ignored
                is A.Fail -> Step.Ignored
                is A.Timeout -> backoffTimeout(ctx, s, a)
            }
            is S.Reconnecting -> when (a) {
                is A.Open -> reconnectingOpen(ctx, s, a)
                is A.Fail -> Step.Go(S.Backoff(0))
                is A.Timeout -> Step.Go(S.Backoff(0))
            }
            is S.Live -> when (a) {
                is A.Open -> Step.Ignored
                is A.Fail -> Step.Go(S.Reconnecting(0))
                is A.Timeout -> Step.Ignored
            }
        }

        companion object {
            val TABLE = Table(
                machine = "Conn",
                states = listOf("Connecting", "Backoff", "Reconnecting", "Live"),
                actions = listOf("Open", "Fail", "Timeout"),
                initial = "Connecting",
                cells = listOf(
                    listOf(Cell.Handle, Cell.Go("Backoff"), Cell.Go("Backoff")),
                    listOf(Cell.Ignore, Cell.Ignore, Cell.Handle),
                    listOf(Cell.Handle, Cell.Go("Backoff"), Cell.Go("Backoff")),
                    listOf(Cell.Ignore, Cell.Go("Reconnecting"), Cell.Ignore),
                ),
            )
        }
    }

    class Impl : Machine() {
        override fun connectingOpen(ctx: Ctx, state: S.Connecting, action: A.Open): Step<S, F> =
            Step.Go(S.Live)

        override fun reconnectingOpen(ctx: Ctx, state: S.Reconnecting, action: A.Open): Step<S, F> =
            Step.Go(S.Live)

        /** The only cell that advances the counter, and the only one that can. */
        override fun backoffTimeout(ctx: Ctx, state: S.Backoff, action: A.Timeout): Step<S, F> =
            if (state.attempt >= ctx.maxAttempts) Step.Stay()
            else Step.Go(S.Reconnecting(state.attempt + 1))
    }
}

object PayloadHoistAdapter : Adapter {
    override val name = "payload-hoist"

    /**
     * Spelled `Long`, not `int`.
     *
     * The adapter reports the type in its own language and `canonicalType`
     * maps it onto the spec vocabulary before the comparison. Rust says `u32`
     * and Swift says `Int` for this same field; all three land on
     * `attempt: int` and share one `.lint` golden. Writing `int` here would
     * pass today and hide the mapping that makes the fixture work.
     */
    override val payloads: Payloads = listOf(
        Triple("Connecting", "attempt", "Long"),
        Triple("Backoff", "attempt", "Long"),
        Triple("Reconnecting", "attempt", "Long"),
    )

    override val table = payloadHoist.Machine.TABLE

    override fun replay(trace: Trace): List<Observed> {
        val ctx = payloadHoist.Ctx(trace.ctx["max_attempts"] ?: 0)
        val m = payloadHoist.Impl()
        var state: payloadHoist.S = stateOf(trace.from, trace.fromFields)
        return trace.steps.map { st ->
            val step = m.step(ctx, state, actionOf(st.action))
            val effects = step.effects.map { it.toString() }
            val expect = when (step) {
                is Step.Stay -> Expect.Stay
                is Step.Ignored -> Expect.Ignored
                is Step.Go -> {
                    state = step.next
                    val want = (st.expect as? Expect.Go)?.fields ?: emptyMap()
                    describe(step.next, want)
                }
            }
            Observed(expect, effects)
        }
    }

    private fun stateOf(name: String, f: Map<String, Long>): payloadHoist.S = when (name) {
        "Connecting" -> payloadHoist.S.Connecting(f["attempt"] ?: 0)
        "Backoff" -> payloadHoist.S.Backoff(f["attempt"] ?: 0)
        "Reconnecting" -> payloadHoist.S.Reconnecting(f["attempt"] ?: 0)
        "Live" -> payloadHoist.S.Live
        else -> error("payload-hoist: unknown state `$name`")
    }

    private fun actionOf(name: String): payloadHoist.A = when (name) {
        "Open" -> payloadHoist.A.Open
        "Fail" -> payloadHoist.A.Fail
        "Timeout" -> payloadHoist.A.Timeout
        else -> error("payload-hoist: unknown action `$name`")
    }

    private fun describe(s: payloadHoist.S, want: Map<String, Long>): Expect.Go {
        fun f(v: Long) = if (want.containsKey("attempt")) mapOf("attempt" to v) else emptyMap()
        return when (s) {
            is payloadHoist.S.Connecting -> Expect.Go("Connecting", f(s.attempt))
            is payloadHoist.S.Backoff -> Expect.Go("Backoff", f(s.attempt))
            is payloadHoist.S.Reconnecting -> Expect.Go("Reconnecting", f(s.attempt))
            is payloadHoist.S.Live -> Expect.Go("Live", emptyMap())
        }
    }
}

/** Every adapter that has landed. A fixture with none is reported as skipped. */
val adapters: List<Adapter> =
    listOf(
        TimerAdapter, ToggleAdapter, RetryAdapter, JobAdapter, EffectsNeverAdapter,
        PayloadHoistAdapter,
    )
