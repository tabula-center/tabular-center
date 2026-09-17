// The colored machine, driven by the colored driver.
//
// `suspend fun main()` rather than any test helper: Kotlin wires it to the
// stdlib's coroutine intrinsics itself, so a suspending entry point costs no
// dependency. That is the same constraint `kotlin/test/RunSuspend.kt` was
// written for, and the language already solves it -- an example has no
// business importing the library's test harness.
//
// `SuspendDriver` is the point. PLAN records it as needing "only the `suspend`
// keyword", and a machine whose prototype is `suspend` is exactly what it is
// for: `step` and `perform` are both suspending here, which is why the plain
// `Driver` could not run this machine at all.
import dev.tabula.SuspendDriver
import generated.gate.A
import generated.gate.Ctx
import generated.gate.GateImpl
import generated.gate.S
import generated.gate.step
import generated.gate.perform

suspend fun main() {
    val cells = GateImpl()
    val ctx = Ctx()
    val driver = SuspendDriver<S, A, generated.gate.F>(S.Closed)

    val progress = driver.dispatch(
        A.Request,
        step = { s, a -> step(cells, ctx, s, a) },
        perform = { f -> perform(cells, ctx, f) },
    )

    Check.eq(driver.state, S.Opening, "Request opens the gate")
    Check.eq(progress.steps, 1, "one action, one step")

    driver.dispatch(
        A.Arrived,
        step = { s, a -> step(cells, ctx, s, a) },
        perform = { f -> perform(cells, ctx, f) },
    )
    Check.eq(driver.state, S.Open, "Arrived completes the opening")

    driver.dispatch(
        A.Request,
        step = { s, a -> step(cells, ctx, s, a) },
        perform = { f -> perform(cells, ctx, f) },
    )
    Check.eq(driver.state, S.Closed, "Request from Open closes it again")

    Check.report("kotlin generated (suspend)")
}
