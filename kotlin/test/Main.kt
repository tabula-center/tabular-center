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

private fun gridMatchesRust() {
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

fun main() {
    runSuspend {
        transitions()
        effectSurface()
    }
    tableAndLints()
    gridMatchesRust()
    drivers()
    val failures = Assert.report("kotlin reference")
    if (failures > 0) kotlin.system.exitProcess(1)
}
