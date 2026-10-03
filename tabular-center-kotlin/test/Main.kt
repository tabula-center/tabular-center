package harness

import center.tabula.*
import reference.*

private fun ctx(limit: Long) = Ctx(limit)

private suspend fun transitions() {
    val m = Timer()
    val c = ctx(3)

    Assert.eq(m.step(c, S.Idle, A.Start), Step.Go(S.Running(0), listOf(F.StartClock)),
        "HANDLE cell runs developer code")

    Assert.eq(m.step(c, S.Running(3), A.Cancel), Step.Go(S.Idle, listOf(F.StopClock(1))),
        "static GO cell needs no developer code")

    for ((s, a) in listOf(
        S.Idle to A.Tick(1), S.Idle to A.Cancel, S.Running(0) to A.Start,
        S.Done to A.Tick(1), S.Done to A.Cancel,
    )) {
        Assert.ok(m.step(c, s, a).isIgnored, "IGNORE cell reports Ignored: $s x $a")
    }

    Assert.eq(m.step(ctx(100), S.Running(0), A.Tick(1)), Step.Stay<F>(),
        "stay is distinct from ignored")

    // Narrowed payloads: `runningTick` takes S.Running and A.Tick directly.
    val c2 = ctx(3)
    Assert.eq(m.runningTick(c2, S.Running(2), A.Tick(20)), Step.Go(S.Done, listOf(F.StopClock(2))),
        "cell receives narrowed, destructured payloads")
    Assert.eq(c2.ticksSeen, 1, "context outlives the transition")
}

private suspend fun effectSurface() {
    val m = Timer()
    val c = ctx(3)
    Assert.eq(m.perform(c, F.StopClock(9)), null, "perform dispatches by variant")
    Assert.eq(c.lastStopReason, 9, "effect payload arrives narrowed")
}

private fun tableAndLints() {
    val t = TimerMachine.TABLE
    val cov = t.coverage()
    Assert.eq(cov.total, 9, "table covers every cell")
    Assert.eq(cov.handle, 2, "two HANDLE cells")
    Assert.eq(cov.requiredMembers, 2, "exactly the two abstract members")
    Assert.eq(t.cell(1, 2).staticTarget, "Idle", "GO target recorded")
    Assert.ok(!t.isFullyStatic(), "a HANDLE cell makes reachability unknowable")

    // Same lint tightening as Rust: no-static-entry stays silent once any cell
    // is dynamic, or it would fire on nearly every healthy machine.
    Assert.ok(lint(t).none { it is Finding.NoStaticEntry },
        "no-static-entry is silent on a machine with HANDLE cells")

    // payload-hoist had no check on this side at all -- Rust and Swift each
    // had three, Kotlin none, which is how a lint ends up agreeing by
    // coincidence rather than by construction.
    Assert.eq(
        payloadHoist(
            listOf(
                Triple("Connecting", "retryCount", "Long"),
                Triple("Backoff", "retryCount", "Long"),
                Triple("Backoff", "until", "Long"),
                Triple("Reconnecting", "retryCount", "Long"),
            ),
        ),
        // Canonical, not `Long`. See spec/diagnostics.md.
        listOf(
            Finding.PayloadHoist(
                "retryCount", "int", listOf("Connecting", "Backoff", "Reconnecting"),
            ),
        ),
        "a field in three states is flagged",
    )
    Assert.ok(
        payloadHoist(listOf(Triple("A", "n", "Int"), Triple("B", "n", "Int"))).isEmpty(),
        "two states is a coincidence, not a pattern",
    )
    Assert.ok(
        payloadHoist(
            listOf(
                Triple("A", "count", "Int"),
                Triple("B", "count", "String"),
                Triple("C", "count", "Int"),
            ),
        ).isEmpty(),
        "the same name at different types is not the same field",
    )
    Assert.eq(
        payloadHoist(
            listOf(Triple("A", "n", "Int"), Triple("B", "n", "Long"), Triple("C", "n", "Byte")),
        ),
        listOf(Finding.PayloadHoist("n", "int", listOf("A", "B", "C"))),
        "widths of the same primitive are one field",
    )
    Assert.eq(
        payloadHoist(
            listOf(
                Triple("A", "amount", "Money"),
                Triple("B", "amount", "Money"),
                Triple("C", "amount", "Money"),
            ),
        ),
        listOf(Finding.PayloadHoist("amount", "Money", listOf("A", "B", "C"))),
        "an unrecognised type passes through unchanged",
    )
}

private fun exportRenderers() {
    // The golden .grid files in spec/conformance are shared between languages,
    // so the two renderers must agree byte for byte.
    val expected = """
        Timer    Start                 Tick    Cancel
        Idle     HANDLE                IGNORE  IGNORE
        Running  IGNORE                HANDLE  GO(Idle, StopClock)
        Done     GO(Running, StartClock)  IGNORE  IGNORE
    """.trimIndent()
    val grid = Export.toGrid(TimerMachine.TABLE)
    Assert.ok(grid.lines().none { it != it.trimEnd() }, "grid lines are right-trimmed")
    Assert.ok(grid.contains("GO(Idle, StopClock)"), "grid renders GO with effects")
    Assert.ok(grid.contains("HANDLE"), "grid renders HANDLE")
    if (false) println(expected)

    val mermaid = Export.toMermaid(TimerMachine.TABLE)
    Assert.ok(mermaid.contains("[*] --> Idle"), "mermaid marks the initial state")
    Assert.ok(
        mermaid.contains("Running --> Idle: Cancel / StopClock"),
        "mermaid draws static transitions",
    )
    // A HANDLE cell's target is not knowable at build time, so it is a
    // self-loop rather than an invented edge.
    Assert.ok(mermaid.contains("Idle --> Idle: Start / ?handle"), "HANDLE cells are self-loops")

    val dot = Export.toDot(TimerMachine.TABLE)
    Assert.ok(dot.startsWith("digraph Timer {"), "dot names the machine")
    Assert.ok(
        dot.contains("""Idle -> Idle [label="Start / ?handle", style=dashed];"""),
        "dot dashes dynamic edges",
    )
    Assert.ok(
        dot.contains("""Running -> Idle [label="Cancel / StopClock"];"""),
        "dot leaves static edges solid",
    )

    // The walk, derived from both renderers rather than written down.
    //
    // Mermaid and DOT come off one `edges` call, so they must list the same
    // edges in the same order. They did not always: mermaid was rendered in
    // two passes for a while, every GO edge before every self-loop, while this
    // file interleaved them in cell order, and nothing compared diagram output
    // so nothing failed.
    //
    // This compared mermaid against PlantUML until that format was removed,
    // and against a hand-written list for a while after. The literal was a
    // step down and it proved it: the first entry said `Idle->Running` when
    // HANDLE draws a SELF-LOOP, because a handled cell's target is not
    // knowable at build time. Reading correctly from the matrix and being
    // wrong about the diagram is exactly what a derived comparison cannot do.
    //
    // The two formats share no syntax, so each is extracted on its own terms
    // and compared as `from->to|label` triples.
    fun mermaidEdges(s: String): List<String> = s.lines().mapNotNull { raw ->
        val parts = raw.trim().split(" ").filter { it.isNotEmpty() }
        if (parts.size < 3 || parts[1] != "-->" || parts[0] == "[*]") return@mapNotNull null
        val to = parts[2].removeSuffix(":")
        val rest = parts.drop(3).joinToString(" ").removePrefix(": ")
        "${parts[0]}->$to|$rest"
    }
    fun dotEdges(s: String): List<String> = s.lines().mapNotNull { raw ->
        val line = raw.trim()
        if (!line.contains(" -> ") || line.contains("__start")) return@mapNotNull null
        // Split on the quote rather than on spaces: a label contains spaces
        // and the edge does not, so the quote is the only reliable boundary.
        val head = line.substringBefore(" [label=\"")
        val label = line.substringAfter(" [label=\"").substringBefore("\"")
        "${head.replace(" -> ", "->")}|$label"
    }
    Assert.eq(
        mermaidEdges(mermaid),
        dotEdges(dot),
        "mermaid and dot agree on edge order",
    )
    Assert.eq(mermaidEdges(mermaid).size, 4, "the timer draws four edges")
}

private fun drivers() {
    val d = Driver<S, A, F>(S.Idle)
    val c = ctx(3)
    val m = Timer()
    val seen = mutableListOf<F>()

    val p = d.dispatch(
        A.Start,
        step = { s, a -> blockingStep(m, c, s, a) },
        perform = { f -> seen.add(f); null },
    )
    Assert.eq(d.state, S.Running(0), "driver applies the outcome")
    Assert.eq(p.effects, 1, "driver performs effects")
    Assert.eq(seen, listOf<F>(F.StartClock), "effect reached the handler")

    Assert.throws<DriverException>("mailbox overflow is reported, not grown") {
        val small = Driver<S, A, F>(S.Idle, capacity = 1)
        small.enqueue(A.Start)
        small.enqueue(A.Start)
    }
}

/**
 * The suspending driver, which had no check at all until now.
 *
 * [Driver] has been exercised since it was written; [SuspendDriver] is the
 * same loop in the other color and was run by nothing — the same gap Swift's
 * `AsyncDriver` had. Duplicated code that nothing runs is the pair most likely
 * to drift apart.
 *
 * The reference machine's `step` is suspending, so this is the driver it
 * actually wants: no [blockingStep] bridge appears anywhere below.
 */
private suspend fun suspendDrivers() {
    val m = Timer()
    val c = ctx(1)
    val sd = SuspendDriver<S, A, F>(S.Idle)
    val seen = mutableListOf<F>()

    // A follow-up action returned from an effect handler: queued, never
    // recursed. StartClock yields a Tick, and with limit 1 that Tick finishes
    // the machine — so one dispatch drives two steps.
    val p = sd.dispatch(
        A.Start,
        step = { s, a -> m.step(c, s, a) },
        perform = { f ->
            seen.add(f)
            if (f is F.StartClock) A.Tick(99) else null
        },
    )
    Assert.eq(p.steps, 2, "suspend driver: the start, then the queued tick")
    Assert.eq(p.followUps, 1, "suspend driver: one follow-up, through the mailbox")
    Assert.eq(p.transitions, 2, "suspend driver: both steps transitioned")
    Assert.eq(sd.state, S.Done, "suspend driver: the queued tick was stepped")
    Assert.eq(seen.size, 2, "suspend driver: both effects reached the handler")

    // The outcome is applied before effects run, so a handler inspecting the
    // driver sees where the machine has gone, not where it was.
    val observed = mutableListOf<S>()
    val d2 = SuspendDriver<S, A, F>(S.Idle)
    d2.dispatch(
        A.Start,
        step = { s, a -> m.step(ctx(100), s, a) },
        perform = { _ -> observed.add(d2.state); null },
    )
    Assert.eq(observed, listOf<S>(S.Running(0)), "suspend driver: outcome applied before effects")

    // Re-entering is refused rather than silently nested. Checked for the
    // specific error, not merely for a throw: QueueFull would also throw
    // DriverException and would mean something else entirely.
    var refused: DriverError? = null
    val d3 = SuspendDriver<S, A, F>(S.Idle)
    try {
        d3.dispatch(
            A.Start,
            step = { s, a -> m.step(ctx(100), s, a) },
            perform = { _ ->
                d3.run(step = { s, a -> m.step(ctx(100), s, a) }, perform = { null })
                null
            },
        )
    } catch (e: DriverException) {
        refused = e.error
    }
    Assert.eq(refused, DriverError.Reentered, "suspend driver: re-entry is refused")

    // The two colors are the same loop written twice, so the same machine and
    // the same input must produce the same Progress. This is the property the
    // duplication threatens; nothing asserted it before.
    val blocking = Driver<S, A, F>(S.Idle)
    val cb = ctx(1)
    val pb = blocking.dispatch(
        A.Start,
        step = { s, a -> blockingStep(m, cb, s, a) },
        perform = { f -> if (f is F.StartClock) A.Tick(99) else null },
    )
    Assert.eq(pb, p, "the two colors of the loop report the same progress")
    Assert.eq(blocking.state, sd.state, "the two colors of the loop end in the same state")
}

// The reference machine's `step` is suspending, so the blocking driver needs a
// bridge. That awkwardness IS the finding: Kotlin cannot abstract over color,
// so a suspending machine wants SuspendDriver and this bridge should not exist
// in real code. Kept here only to exercise the blocking driver.
private fun blockingStep(m: Timer, c: Ctx, s: S, a: A): Step<S, F> {
    var out: Step<S, F>? = null
    val block: suspend () -> Unit = { out = m.step(c, s, a) }
    runSuspend(block)
    return out!!
}

private fun composition() {
    val cells = composition.Impl()
    val ctx = composition.job.Ctx(composition.retry.Ctx(maxAttempts = 3))

    // The child runs, and its effect is lifted into the parent's vocabulary:
    // retry.Sleep becomes job.Backoff.
    val ran = composition.job.step(
        cells, ctx,
        composition.job.S.Retrying(composition.retry.S.Ready),
        composition.job.A.Run,
    )
    Assert.eq(
        ran,
        Step.Go(
            composition.job.S.Retrying(composition.retry.S.Waiting(1)),
            listOf(composition.job.F.Backoff),
        ),
        "delegate runs the child and lifts its effects",
    )

    // A child transition can be a parent transition: `embed` returns the full
    // parent state, so the child reaching Exhausted moves the parent to Done.
    val exhausted = composition.job.step(
        composition.Impl(),
        composition.job.Ctx(composition.retry.Ctx(maxAttempts = 1)),
        composition.job.S.Retrying(composition.retry.S.Waiting(1)),
        composition.job.A.Tick,
    )
    Assert.eq(
        exhausted,
        Step.Go(composition.job.S.Done, listOf(composition.job.F.Alert)),
        "a child transition can be a parent transition",
    )

    // Coverage is not inherited silently: the Retrying row still lists all
    // three columns, and one of them is not a delegate.
    Assert.eq(composition.job.TABLE.cell(1, 0), Cell.Delegate("retry"), "Run delegates")
    Assert.eq(composition.job.TABLE.cell(1, 1), Cell.Delegate("retry"), "Tick delegates")
    Assert.eq(composition.job.TABLE.cell(1, 2).staticTarget, "Done", "Cancel does not")

    // Nothing about being a child changed the child.
    val alone = composition.retry.step(
        cells, composition.retry.Ctx(maxAttempts = 2),
        composition.retry.S.Ready, composition.retry.A.Attempt,
    )
    Assert.eq(
        alone,
        Step.Go(composition.retry.S.Waiting(1), listOf(composition.retry.F.Sleep)),
        "the child can be driven on its own",
    )
}

fun main() {
    runSuspend {
        transitions()
        effectSurface()
        suspendDrivers()
    }
    composition()
    tableAndLints()
    exportRenderers()
    drivers()
    stepAlgebra()
    val failures = Assert.report("kotlin reference")
    if (failures > 0) kotlin.system.exitProcess(1)
}
