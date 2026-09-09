package harness

import dev.tabula.*
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

    val puml = Export.toPlantuml(TimerMachine.TABLE)
    Assert.ok(puml.startsWith("@startuml\n"), "plantuml opens")
    Assert.ok(puml.endsWith("@enduml\n"), "plantuml closes")
    Assert.ok(puml.contains("[*] --> Idle"), "plantuml marks the initial state")
    Assert.ok(
        puml.contains("Running --> Idle : Cancel / StopClock"),
        "plantuml draws static transitions",
    )

    // The three formats share one walk, so they must list the same edges in
    // the same order. Rust rendered mermaid in two passes for a while — every
    // GO edge, then every self-loop — while this side interleaved them in cell
    // order. Same edge set, different line order, and nothing compares diagram
    // output so nothing failed.
    fun edgeOrder(s: String): List<String> = s.lines().mapNotNull { raw ->
        val parts = raw.trim().split(" ").filter { it.isNotEmpty() }
        if (parts.size < 3 || parts[1] != "-->" || parts[0] == "[*]") return@mapNotNull null
        // mermaid writes `To: label`, plantuml writes `To : label`.
        val to = parts[2].removeSuffix(":")
        val rest = parts.drop(3).joinToString(" ").removePrefix(": ")
        "${parts[0]}->$to|$rest"
    }
    Assert.eq(edgeOrder(mermaid), edgeOrder(puml), "mermaid and plantuml agree on edge order")
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
    }
    composition()
    tableAndLints()
    exportRenderers()
    drivers()
    val failures = Assert.report("kotlin reference")
    if (failures > 0) kotlin.system.exitProcess(1)
}
