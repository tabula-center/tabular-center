package conformance

import dev.tabula.*
import dev.tabula.testing.*

/**
 * The fixture machines, written in the shape KSP will generate.
 *
 * Each is the Kotlin counterpart of a Rust adapter in `tabular-center-conformance`.
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
     * `tabular-center::payload-hoist` among those. Rust has passed its `PAYLOADS` to
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
 * cannot be written at all, because an empty one is `tabular-center::empty-emit`.
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
// payload-hoist.tbl -- the only coverage for `tabular-center::payload-hoist`
// ---------------------------------------------------------------------------

/**
 * `attempt` in three states, which is what the lint is looking for.
 *
 * The machine is deliberately a little wrong: a retry counter that outlives
 * every transition belongs in Context, and three states carrying their own
 * copy is the smell `tabular-center::payload-hoist` names. The fixture models the
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

// ---------------------------------------------------------------------------
// dead-column.tbl -- the only coverage for `tabular-center::dead-column`
// ---------------------------------------------------------------------------

/**
 * A vending machine whose refund button was never wired up.
 *
 * `Refund` is IGNORE in every row, which is the lint. The rest of the matrix
 * is shaped to stay quiet so the fixture says one thing -- see the notes in
 * `dead-column.tbl`, including why 6 of 9 IGNORE (66%) sits deliberately close
 * to `IGNORE_HEAVY_PERCENT` rather than comfortably below it.
 *
 * `credit` is on one state only. Three would trip `payload-hoist` and the
 * fixture would then be testing two things, neither of them cleanly.
 */
object deadColumn {
    sealed interface S {
        data object Idle : S
        data class Charged(val credit: Long) : S
        data object Dispensing : S
    }
    sealed interface A {
        data object Insert : A
        data object Select : A
        data object Refund : A
    }
    sealed interface F

    class Ctx(val price: Long)

    abstract class Machine {
        abstract fun idleInsert(ctx: Ctx, state: S.Idle, action: A.Insert): Step<S, F>
        abstract fun chargedSelect(ctx: Ctx, state: S.Charged, action: A.Select): Step<S, F>

        fun step(ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
            is S.Idle -> when (a) {
                is A.Insert -> idleInsert(ctx, s, a)
                is A.Select -> Step.Ignored
                is A.Refund -> Step.Ignored
            }
            is S.Charged -> when (a) {
                is A.Insert -> Step.Ignored
                is A.Select -> chargedSelect(ctx, s, a)
                is A.Refund -> Step.Ignored
            }
            is S.Dispensing -> when (a) {
                is A.Insert -> Step.Go(S.Idle)
                is A.Select -> Step.Ignored
                is A.Refund -> Step.Ignored
            }
        }

        companion object {
            val TABLE = Table(
                machine = "Vend",
                states = listOf("Idle", "Charged", "Dispensing"),
                actions = listOf("Insert", "Select", "Refund"),
                initial = "Idle",
                cells = listOf(
                    listOf(Cell.Handle, Cell.Ignore, Cell.Ignore),
                    listOf(Cell.Ignore, Cell.Handle, Cell.Ignore),
                    listOf(Cell.Go("Idle"), Cell.Ignore, Cell.Ignore),
                ),
            )
        }
    }

    class Impl : Machine() {
        override fun idleInsert(ctx: Ctx, state: S.Idle, action: A.Insert): Step<S, F> =
            Step.Go(S.Charged(1))

        /**
         * `stay`, not `ignored`, when the credit is short.
         *
         * The distinction the third trace exists for: this cell is HANDLE and
         * refuses, while `Charged`/`Insert` beside it is IGNORE and never
         * runs. An implementation collapsing the two passes every other
         * fixture.
         */
        override fun chargedSelect(ctx: Ctx, state: S.Charged, action: A.Select): Step<S, F> =
            if (state.credit >= ctx.price) Step.Go(S.Dispensing) else Step.Stay()
    }
}

object DeadColumnAdapter : Adapter {
    override val name = "dead-column"

    /** One state, so `payload-hoist` stays out of this fixture's way. */
    override val payloads: Payloads = listOf(Triple("Charged", "credit", "Long"))

    override val table = deadColumn.Machine.TABLE

    override fun replay(trace: Trace): List<Observed> {
        val ctx = deadColumn.Ctx(trace.ctx["price"] ?: 0)
        val m = deadColumn.Impl()
        var state: deadColumn.S = stateOf(trace.from, trace.fromFields)
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

    private fun stateOf(name: String, f: Map<String, Long>): deadColumn.S = when (name) {
        "Idle" -> deadColumn.S.Idle
        "Charged" -> deadColumn.S.Charged(f["credit"] ?: 0)
        "Dispensing" -> deadColumn.S.Dispensing
        else -> error("dead-column: unknown state `$name`")
    }

    private fun actionOf(name: String): deadColumn.A = when (name) {
        "Insert" -> deadColumn.A.Insert
        "Select" -> deadColumn.A.Select
        "Refund" -> deadColumn.A.Refund
        else -> error("dead-column: unknown action `$name`")
    }

    private fun describe(s: deadColumn.S, want: Map<String, Long>): Expect.Go = when (s) {
        is deadColumn.S.Idle -> Expect.Go("Idle", emptyMap())
        is deadColumn.S.Charged ->
            Expect.Go("Charged", if (want.containsKey("credit")) mapOf("credit" to s.credit) else emptyMap())
        is deadColumn.S.Dispensing -> Expect.Go("Dispensing", emptyMap())
    }
}

// ---------------------------------------------------------------------------
// ignore-heavy.tbl
// ---------------------------------------------------------------------------

/**
 * The `tabular-center::ignore-heavy` fixture: 15 of 20 cells `IGNORE` (75%).
 *
 * Four states each answering one action. Written the way KSP generates it --
 * one abstract member per `HANDLE` cell, a `when` with no `else` -- so the
 * dispatcher is exhaustive over a matrix that is mostly `Step.Ignored`, which
 * is the shape the lint's "consider splitting this machine" is about.
 *
 * 4x5 rather than the suite's usual 3x3 because the shape is forced: see the
 * note at the top of `ignore-heavy.tbl`. No payloads, so `payload-hoist`
 * cannot fire, and the `HANDLE`s make the matrix not fully static, which gates
 * `no-static-entry` off.
 */
object ignoreHeavy {
    sealed interface S {
        data object Idle : S
        data object Armed : S
        data object Firing : S
        data object Spent : S
    }
    sealed interface A {
        data object Arm : A
        data object Tick : A
        data object Fire : A
        data object Reset : A
        data object Abort : A
    }

    /** No effects anywhere in the matrix. */
    sealed interface F

    object Ctx

    abstract class Machine {
        abstract fun idleArm(ctx: Ctx, state: S.Idle, action: A.Arm): Step<S, F>
        abstract fun armedTick(ctx: Ctx, state: S.Armed, action: A.Tick): Step<S, F>
        abstract fun firingFire(ctx: Ctx, state: S.Firing, action: A.Fire): Step<S, F>

        fun step(ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
            is S.Idle -> when (a) {
                is A.Arm -> idleArm(ctx, s, a)
                is A.Tick -> Step.Ignored
                is A.Fire -> Step.Ignored
                is A.Reset -> Step.Ignored
                is A.Abort -> Step.Ignored
            }
            is S.Armed -> when (a) {
                is A.Arm -> Step.Ignored
                is A.Tick -> armedTick(ctx, s, a)
                is A.Fire -> Step.Ignored
                is A.Reset -> Step.Ignored
                is A.Abort -> Step.Go(S.Idle)
            }
            is S.Firing -> when (a) {
                is A.Arm -> Step.Ignored
                is A.Tick -> Step.Ignored
                is A.Fire -> firingFire(ctx, s, a)
                is A.Reset -> Step.Ignored
                is A.Abort -> Step.Ignored
            }
            is S.Spent -> when (a) {
                is A.Arm -> Step.Ignored
                is A.Tick -> Step.Ignored
                is A.Fire -> Step.Ignored
                is A.Reset -> Step.Go(S.Idle)
                is A.Abort -> Step.Ignored
            }
        }

        companion object {
            val TABLE = Table(
                machine = "Poll",
                states = listOf("Idle", "Armed", "Firing", "Spent"),
                actions = listOf("Arm", "Tick", "Fire", "Reset", "Abort"),
                initial = "Idle",
                cells = listOf(
                    listOf(Cell.Handle, Cell.Ignore, Cell.Ignore, Cell.Ignore, Cell.Ignore),
                    listOf(Cell.Ignore, Cell.Handle, Cell.Ignore, Cell.Ignore, Cell.Go("Idle")),
                    listOf(Cell.Ignore, Cell.Ignore, Cell.Handle, Cell.Ignore, Cell.Ignore),
                    listOf(Cell.Ignore, Cell.Ignore, Cell.Ignore, Cell.Go("Idle"), Cell.Ignore),
                ),
            )
        }
    }

    class Impl : Machine() {
        override fun idleArm(ctx: Ctx, state: S.Idle, action: A.Arm): Step<S, F> =
            Step.Go(S.Armed)

        /**
         * `stay`, not `ignored`: the tick is handled and changes nothing.
         * `one-action-per-state` asserts exactly that, one step after an
         * `Arm => ignored` from the same state -- the two outcomes side by side.
         */
        override fun armedTick(ctx: Ctx, state: S.Armed, action: A.Tick): Step<S, F> =
            Step.Stay()

        override fun firingFire(ctx: Ctx, state: S.Firing, action: A.Fire): Step<S, F> =
            Step.Go(S.Spent)
    }
}

object IgnoreHeavyAdapter : Adapter {
    override val name = "ignore-heavy"
    override val table = ignoreHeavy.Machine.TABLE

    override fun replay(trace: Trace): List<Observed> {
        val m = ignoreHeavy.Impl()
        var state: ignoreHeavy.S = stateOf(trace.from)
        return trace.steps.map { st ->
            val step = m.step(ignoreHeavy.Ctx, state, actionOf(st.action))
            val effects = step.effects.map { it.toString() }
            val expect = when (step) {
                is Step.Stay -> Expect.Stay
                is Step.Ignored -> Expect.Ignored
                is Step.Go -> {
                    state = step.next
                    Expect.Go(nameOf(step.next), emptyMap())
                }
            }
            Observed(expect, effects)
        }
    }

    private fun stateOf(name: String): ignoreHeavy.S = when (name) {
        "Idle" -> ignoreHeavy.S.Idle
        "Armed" -> ignoreHeavy.S.Armed
        "Firing" -> ignoreHeavy.S.Firing
        "Spent" -> ignoreHeavy.S.Spent
        else -> error("ignore-heavy: unknown state `$name`")
    }

    private fun actionOf(name: String): ignoreHeavy.A = when (name) {
        "Arm" -> ignoreHeavy.A.Arm
        "Tick" -> ignoreHeavy.A.Tick
        "Fire" -> ignoreHeavy.A.Fire
        "Reset" -> ignoreHeavy.A.Reset
        "Abort" -> ignoreHeavy.A.Abort
        else -> error("ignore-heavy: unknown action `$name`")
    }

    // Exhaustive `when` rather than `toString()`, so a state added to `S`
    // without a name here fails to compile instead of printing a data-object
    // rendering the fixture would never match.
    private fun nameOf(s: ignoreHeavy.S): String = when (s) {
        is ignoreHeavy.S.Idle -> "Idle"
        is ignoreHeavy.S.Armed -> "Armed"
        is ignoreHeavy.S.Firing -> "Firing"
        is ignoreHeavy.S.Spent -> "Spent"
    }
}

// ---------------------------------------------------------------------------
// no-static-exit.tbl
// ---------------------------------------------------------------------------

/**
 * The `tabular-center::no-static-exit` fixture: `Fault` can be entered and, as far as
 * the matrix can prove, never left.
 *
 * Its row is `[IGNORE, EMIT(Alarm), IGNORE]`. `EMIT` is `stay` plus an effect,
 * never a transition -- which is why it compiles to `Step.Stay(listOf(...))`
 * below and not to `Step.Go(S.Fault, ...)`. The `emit-stays-put` trace fails
 * an implementation that confuses the two.
 *
 * `Fault`'s `EMIT` is the only live cell in its row, and that single cell is
 * what keeps `dead-row` from subsuming this lint.
 */
object noStaticExit {
    sealed interface S {
        data object Idle : S
        data object Blinking : S
        data object Fault : S
    }
    sealed interface A {
        data object Start : A
        data object Pulse : A
        data object Clear : A
    }
    sealed interface F {
        data object Flash : F
        data object Alarm : F
    }

    object Ctx

    abstract class Machine {
        abstract fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start): Step<S, F>

        fun step(ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
            is S.Idle -> when (a) {
                is A.Start -> idleStart(ctx, s, a)
                is A.Pulse -> Step.Ignored
                is A.Clear -> Step.Ignored
            }
            is S.Blinking -> when (a) {
                is A.Start -> Step.Ignored
                is A.Pulse -> Step.Stay(listOf(F.Flash))
                is A.Clear -> Step.Go(S.Idle)
            }
            is S.Fault -> when (a) {
                is A.Start -> Step.Ignored
                is A.Pulse -> Step.Stay(listOf(F.Alarm))
                is A.Clear -> Step.Ignored
            }
        }

        companion object {
            val TABLE = Table(
                machine = "Beacon",
                states = listOf("Idle", "Blinking", "Fault"),
                actions = listOf("Start", "Pulse", "Clear"),
                initial = "Idle",
                cells = listOf(
                    listOf(Cell.Handle, Cell.Ignore, Cell.Ignore),
                    listOf(Cell.Ignore, Cell.Emit(listOf("Flash")), Cell.Go("Idle")),
                    listOf(Cell.Ignore, Cell.Emit(listOf("Alarm")), Cell.Ignore),
                ),
            )
        }
    }

    class Impl : Machine() {
        /**
         * The only dynamic cell, and the reason the matrix is not fully static
         * -- which is what keeps `no-static-entry` quiet about `Fault`, a state
         * nothing in the matrix enters.
         */
        override fun idleStart(ctx: Ctx, state: S.Idle, action: A.Start): Step<S, F> =
            Step.Go(S.Blinking)
    }
}

object NoStaticExitAdapter : Adapter {
    override val name = "no-static-exit"
    override val table = noStaticExit.Machine.TABLE

    override fun replay(trace: Trace): List<Observed> {
        val m = noStaticExit.Impl()
        var state: noStaticExit.S = stateOf(trace.from)
        return trace.steps.map { st ->
            val step = m.step(noStaticExit.Ctx, state, actionOf(st.action))
            val effects = step.effects.map { it.toString() }
            val expect = when (step) {
                is Step.Stay -> Expect.Stay
                is Step.Ignored -> Expect.Ignored
                is Step.Go -> {
                    state = step.next
                    Expect.Go(nameOf(step.next), emptyMap())
                }
            }
            Observed(expect, effects)
        }
    }

    private fun stateOf(name: String): noStaticExit.S = when (name) {
        "Idle" -> noStaticExit.S.Idle
        "Blinking" -> noStaticExit.S.Blinking
        "Fault" -> noStaticExit.S.Fault
        else -> error("no-static-exit: unknown state `$name`")
    }

    private fun actionOf(name: String): noStaticExit.A = when (name) {
        "Start" -> noStaticExit.A.Start
        "Pulse" -> noStaticExit.A.Pulse
        "Clear" -> noStaticExit.A.Clear
        else -> error("no-static-exit: unknown action `$name`")
    }

    private fun nameOf(s: noStaticExit.S): String = when (s) {
        is noStaticExit.S.Idle -> "Idle"
        is noStaticExit.S.Blinking -> "Blinking"
        is noStaticExit.S.Fault -> "Fault"
    }
}

// ---------------------------------------------------------------------------
// no-static-entry.tbl
// ---------------------------------------------------------------------------

/**
 * The `tabular-center::no-static-entry` fixture: `Jammed` has a row and a way out, and
 * nothing in the matrix leads in.
 *
 * The matrix is **fully static** -- no `HANDLE`, `DELEGATE` or `UNREACHABLE`
 * -- which is the gate the lint needs before it may speak. `effects-never`
 * pins that gate shut; this pins it open. It also means [Machine] has no
 * abstract members at all: every cell is one word, and there is nothing for
 * [Impl] to write.
 *
 * `Jammed`'s `EMIT(Thud)` compiles to `Step.Stay(listOf(F.Thud))`, not to a
 * `Go` into `Jammed` -- a reachability walk that counted it as an incoming
 * edge would go silent on this fixture.
 */
object noStaticEntry {
    sealed interface S {
        data object Closed : S
        data object Open : S
        data object Jammed : S
    }
    sealed interface A {
        data object Push : A
        data object Pull : A
        data object Kick : A
    }
    sealed interface F {
        data object Thud : F
    }

    object Ctx

    abstract class Machine {
        fun step(ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
            is S.Closed -> when (a) {
                is A.Push -> Step.Go(S.Open)
                is A.Pull -> Step.Ignored
                is A.Kick -> Step.Ignored
            }
            is S.Open -> when (a) {
                is A.Push -> Step.Ignored
                is A.Pull -> Step.Go(S.Closed)
                is A.Kick -> Step.Ignored
            }
            is S.Jammed -> when (a) {
                is A.Push -> Step.Stay(listOf(F.Thud))
                is A.Pull -> Step.Ignored
                is A.Kick -> Step.Go(S.Closed)
            }
        }

        companion object {
            val TABLE = Table(
                machine = "Door",
                states = listOf("Closed", "Open", "Jammed"),
                actions = listOf("Push", "Pull", "Kick"),
                initial = "Closed",
                cells = listOf(
                    listOf(Cell.Go("Open"), Cell.Ignore, Cell.Ignore),
                    listOf(Cell.Ignore, Cell.Go("Closed"), Cell.Ignore),
                    listOf(Cell.Emit(listOf("Thud")), Cell.Ignore, Cell.Go("Closed")),
                ),
            )
        }
    }

    /** Nothing to implement: every cell is static. */
    class Impl : Machine()
}

object NoStaticEntryAdapter : Adapter {
    override val name = "no-static-entry"
    override val table = noStaticEntry.Machine.TABLE

    override fun replay(trace: Trace): List<Observed> {
        val m = noStaticEntry.Impl()
        var state: noStaticEntry.S = stateOf(trace.from)
        return trace.steps.map { st ->
            val step = m.step(noStaticEntry.Ctx, state, actionOf(st.action))
            val effects = step.effects.map { it.toString() }
            val expect = when (step) {
                is Step.Stay -> Expect.Stay
                is Step.Ignored -> Expect.Ignored
                is Step.Go -> {
                    state = step.next
                    Expect.Go(nameOf(step.next), emptyMap())
                }
            }
            Observed(expect, effects)
        }
    }

    private fun stateOf(name: String): noStaticEntry.S = when (name) {
        "Closed" -> noStaticEntry.S.Closed
        "Open" -> noStaticEntry.S.Open
        "Jammed" -> noStaticEntry.S.Jammed
        else -> error("no-static-entry: unknown state `$name`")
    }

    private fun actionOf(name: String): noStaticEntry.A = when (name) {
        "Push" -> noStaticEntry.A.Push
        "Pull" -> noStaticEntry.A.Pull
        "Kick" -> noStaticEntry.A.Kick
        else -> error("no-static-entry: unknown action `$name`")
    }

    private fun nameOf(s: noStaticEntry.S): String = when (s) {
        is noStaticEntry.S.Closed -> "Closed"
        is noStaticEntry.S.Open -> "Open"
        is noStaticEntry.S.Jammed -> "Jammed"
    }
}

// ---------------------------------------------------------------------------
// unreachable-heavy.tbl
// ---------------------------------------------------------------------------

/**
 * The `tabular-center::unreachable-heavy` fixture: three `UNREACHABLE` cells of twelve,
 * which is `UNREACHABLE_HEAVY_PERCENT` exactly -- on the boundary, so `>` in
 * place of `>=` fails it.
 *
 * `UNREACHABLE` generates no member and compiles to a trap with the normative
 * message from `spec/cells.md`. The traces never reach one; the fixture's
 * claim about them is carried by the table and the goldens.
 */
object unreachableHeavy {
    sealed interface S {
        data object Down : S
        data object Dialing : S
        data object Up : S
    }
    sealed interface A {
        data object Dial : A
        data object Ack : A
        data object Hangup : A
        data object Ping : A
    }
    sealed interface F {
        data object Pong : F
    }

    class Ctx(val accept: Boolean)

    abstract class Machine {
        abstract fun dialingAck(ctx: Ctx, state: S.Dialing, action: A.Ack): Step<S, F>

        fun step(ctx: Ctx, s: S, a: A): Step<S, F> = when (s) {
            is S.Down -> when (a) {
                is A.Dial -> Step.Go(S.Dialing)
                is A.Ack -> error("tabula: Down x Ack was declared UNREACHABLE but occurred")
                is A.Hangup -> Step.Ignored
                is A.Ping -> Step.Ignored
            }
            is S.Dialing -> when (a) {
                is A.Dial -> error("tabula: Dialing x Dial was declared UNREACHABLE but occurred")
                is A.Ack -> dialingAck(ctx, s, a)
                is A.Hangup -> Step.Go(S.Down)
                is A.Ping -> Step.Ignored
            }
            is S.Up -> when (a) {
                is A.Dial -> error("tabula: Up x Dial was declared UNREACHABLE but occurred")
                is A.Ack -> Step.Ignored
                is A.Hangup -> Step.Go(S.Down)
                is A.Ping -> Step.Stay(listOf(F.Pong))
            }
        }

        companion object {
            val TABLE = Table(
                machine = "Link",
                states = listOf("Down", "Dialing", "Up"),
                actions = listOf("Dial", "Ack", "Hangup", "Ping"),
                initial = "Down",
                cells = listOf(
                    listOf(Cell.Go("Dialing"), Cell.Unreachable, Cell.Ignore, Cell.Ignore),
                    listOf(Cell.Unreachable, Cell.Handle, Cell.Go("Down"), Cell.Ignore),
                    listOf(Cell.Unreachable, Cell.Ignore, Cell.Go("Down"), Cell.Emit(listOf("Pong"))),
                ),
            )
        }
    }

    class Impl : Machine() {
        /** `stay`, not `ignored`, when refused: the cell ran and chose not to move. */
        override fun dialingAck(ctx: Ctx, state: S.Dialing, action: A.Ack): Step<S, F> =
            if (ctx.accept) Step.Go(S.Up) else Step.Stay()
    }
}

object UnreachableHeavyAdapter : Adapter {
    override val name = "unreachable-heavy"
    override val table = unreachableHeavy.Machine.TABLE

    override fun replay(trace: Trace): List<Observed> {
        val m = unreachableHeavy.Impl()
        val ctx = unreachableHeavy.Ctx((trace.ctx["accept"] ?: 0L) != 0L)
        var state: unreachableHeavy.S = stateOf(trace.from)
        return trace.steps.map { st ->
            val step = m.step(ctx, state, actionOf(st.action))
            val effects = step.effects.map { it.toString() }
            val expect = when (step) {
                is Step.Stay -> Expect.Stay
                is Step.Ignored -> Expect.Ignored
                is Step.Go -> {
                    state = step.next
                    Expect.Go(nameOf(step.next), emptyMap())
                }
            }
            Observed(expect, effects)
        }
    }

    private fun stateOf(name: String): unreachableHeavy.S = when (name) {
        "Down" -> unreachableHeavy.S.Down
        "Dialing" -> unreachableHeavy.S.Dialing
        "Up" -> unreachableHeavy.S.Up
        else -> error("unreachable-heavy: unknown state `$name`")
    }

    private fun actionOf(name: String): unreachableHeavy.A = when (name) {
        "Dial" -> unreachableHeavy.A.Dial
        "Ack" -> unreachableHeavy.A.Ack
        "Hangup" -> unreachableHeavy.A.Hangup
        "Ping" -> unreachableHeavy.A.Ping
        else -> error("unreachable-heavy: unknown action `$name`")
    }

    private fun nameOf(s: unreachableHeavy.S): String = when (s) {
        is unreachableHeavy.S.Down -> "Down"
        is unreachableHeavy.S.Dialing -> "Dialing"
        is unreachableHeavy.S.Up -> "Up"
    }
}

/** Every adapter that has landed. A fixture with none is reported as skipped. */
val adapters: List<Adapter> =
    listOf(
        TimerAdapter, ToggleAdapter, RetryAdapter, JobAdapter, EffectsNeverAdapter,
        PayloadHoistAdapter, DeadColumnAdapter, IgnoreHeavyAdapter, NoStaticExitAdapter,
        NoStaticEntryAdapter, UnreachableHeavyAdapter,
    )
