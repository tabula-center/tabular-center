package conformance

import composition.Impl
import composition.job
import composition.retry
import dev.tabula.Step

/**
 * Adapters for `retry.tbl` and `nested-delegate.tbl`.
 *
 * Two adapters over one pair of machines, because the child must be conformant
 * **on its own**: being composed does not change it, and a child that only
 * works inside its parent is not a reusable machine.
 *
 * The machines live in `test/Composition.kt` rather than here — they are the
 * KSP specification first and conformance fixtures second.
 */

object RetryAdapter : Adapter {
    override val name = "retry"
    override val table = retry.TABLE

    override fun replay(trace: Trace): List<Observed> {
        val ctx = retry.Ctx(trace.ctx["max_attempts"] ?: 1)
        val cells = Impl()
        var state: retry.S = stateOf(trace.from, trace.fromFields)
        return trace.steps.map { st ->
            val action = when (st.action) {
                "Attempt" -> retry.A.Attempt
                "Elapsed" -> retry.A.Elapsed
                "Abort" -> retry.A.Abort
                else -> error("retry: unknown action `${st.action}`")
            }
            val step = retry.step(cells, ctx, state, action)
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

    private fun stateOf(name: String, f: Map<String, Long>): retry.S = when (name) {
        "Ready" -> retry.S.Ready
        "Exhausted" -> retry.S.Exhausted
        "Waiting" -> retry.S.Waiting(f["attempt"] ?: 1)
        else -> error("retry: unknown state `$name`")
    }

    private fun describe(s: retry.S, want: Map<String, Long>): Expect.Go = when (s) {
        is retry.S.Ready -> Expect.Go("Ready", emptyMap())
        is retry.S.Exhausted -> Expect.Go("Exhausted", emptyMap())
        is retry.S.Waiting ->
            Expect.Go("Waiting", if (want.containsKey("attempt")) mapOf("attempt" to s.attempt) else emptyMap())
    }
}

object JobAdapter : Adapter {
    override val name = "nested-delegate"
    override val table = job.TABLE

    override fun replay(trace: Trace): List<Observed> {
        val ctx = job.Ctx(retry.Ctx(trace.ctx["max_attempts"] ?: 1))
        val cells = Impl()

        // `from Retrying child_attempt=N` starts the child in Waiting(N);
        // absent means Ready. The trace format is flat by design, so a nested
        // state is addressed by a prefixed field rather than by nesting.
        var state: job.S = when (trace.from) {
            "Idle" -> job.S.Idle
            "Done" -> job.S.Done
            "Retrying" -> job.S.Retrying(
                trace.fromFields["child_attempt"]
                    ?.let { retry.S.Waiting(it) }
                    ?: retry.S.Ready
            )
            else -> error("job: unknown state `${trace.from}`")
        }

        return trace.steps.map { st ->
            val action = when (st.action) {
                "Run" -> job.A.Run
                "Tick" -> job.A.Tick
                "Cancel" -> job.A.Cancel
                else -> error("job: unknown action `${st.action}`")
            }
            val step = job.step(cells, ctx, state, action)
            val effects = step.effects.map { it.toString() }
            val expect = when (step) {
                is Step.Stay -> Expect.Stay
                is Step.Ignored -> Expect.Ignored
                is Step.Go -> {
                    state = step.next
                    val name = when (step.next) {
                        is job.S.Idle -> "Idle"
                        is job.S.Done -> "Done"
                        is job.S.Retrying -> "Retrying"
                    }
                    Expect.Go(name, emptyMap())
                }
            }
            Observed(expect, effects)
        }
    }
}
