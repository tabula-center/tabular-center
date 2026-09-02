/**
 * Tests for the four examples.
 *
 * The same assertions as the Rust examples, deliberately: the two
 * implementations agreeing on worked examples is the same kind of check that
 * `spec/conformance` performs on fixtures, and it is where the last two design
 * findings came from.
 */
package examples

import dev.tabula.Step

// Fully-qualified references below rather than imports: `trafficlight`,
// `timer` and `retry` are packages while `auth` and `session` are objects, and
// mixing the two import forms reads worse than just spelling them out. The
// examples are laid out the way a reader wants them, not the way this harness
// would prefer.

private var failures = 0
private var checks = 0

private fun <T> eq(actual: T, expected: T, what: String) {
    checks++
    if (actual != expected) {
        failures++
        println("FAIL $what")
        println("       got      $actual")
        println("       expected $expected")
    }
}

private fun ok(cond: Boolean, what: String) {
    checks++
    if (!cond) { failures++; println("FAIL $what") }
}

private fun trafficLight() {
    run {
        val ctx = examples.trafficlight.Ctx()
        val c = examples.trafficlight.Controller()
        var s: examples.trafficlight.S = examples.trafficlight.S.Red
        repeat(6) {
            val step = examples.trafficlight.step(c, ctx, s, examples.trafficlight.A.Advance)
            s = (step as Step.Go).next
        }
        eq(s, examples.trafficlight.S.Red, "traffic light: two full cycles return to red")
        eq(ctx.cycles, 2, "traffic light: context counted both cycles")
    }

    for (from in listOf(examples.trafficlight.S.Red, examples.trafficlight.S.Green, examples.trafficlight.S.Amber)) {
        val step = examples.trafficlight.step(
            examples.trafficlight.Controller(), examples.trafficlight.Ctx(), from, examples.trafficlight.A.Fault,
        )
        eq(step, Step.Go(examples.trafficlight.S.Red), "traffic light: fault from $from goes red")
    }

    val cov = examples.trafficlight.TABLE.coverage()
    eq(cov.total, 6, "traffic light: six cells")
    eq(cov.requiredMembers, 1, "traffic light: one implementation")
}

private fun timer() {
    val m = examples.timer.Impl()

    eq(
        examples.timer.step(m, examples.timer.Ctx(10), examples.timer.S.Running(0), examples.timer.A.Tick(1)),
        Step.Stay<examples.timer.F>(),
        "timer: a tick below the limit stays",
    )
    ok(
        examples.timer.step(m, examples.timer.Ctx(10), examples.timer.S.Running(0), examples.timer.A.Tick(1)) !is Step.Ignored,
        "timer: a tick while running is meaningful, not ignored",
    )
    eq(
        examples.timer.step(m, examples.timer.Ctx(3), examples.timer.S.Running(2), examples.timer.A.Tick(9)),
        Step.Go(examples.timer.S.Done, listOf(examples.timer.F.StopClock(examples.timer.Reason.Elapsed))),
        "timer: the limit finishes the timer",
    )
    // The same effect, a different reason. The payload is what tells them apart.
    eq(
        examples.timer.step(m, examples.timer.Ctx(100), examples.timer.S.Running(0), examples.timer.A.Cancel).effects,
        listOf(examples.timer.F.StopClock(examples.timer.Reason.Cancelled)),
        "timer: cancelling stops the clock for a different reason",
    )

    val ctx = examples.timer.Ctx(1)
    examples.timer.perform(m, ctx, examples.timer.F.StopClock(examples.timer.Reason.Elapsed))
    eq(ctx.log, listOf("stop:Elapsed"), "timer: effect handlers receive narrowed payloads")

    for (pair in listOf(
        examples.timer.S.Idle to examples.timer.A.Tick(1),
        examples.timer.S.Idle to examples.timer.A.Cancel,
        examples.timer.S.Done to examples.timer.A.Cancel,
    )) {
        ok(
            examples.timer.step(m, examples.timer.Ctx(1), pair.first, pair.second) is Step.Ignored,
            "timer: ${pair.second} means nothing in ${pair.first}",
        )
    }
}

private fun retry() {
    val (state3, ctx3) = examples.retry.run(3)
    eq(state3, examples.retry.S.Exhausted, "retry: backs off and gives up on its own")
    eq(
        ctx3.performed,
        listOf("sleep:100", "sleep:200", "sleep:300", "give-up"),
        "retry: one dispatch, four effects, all follow-ups through the mailbox",
    )

    val (_, ctx4) = examples.retry.run(4)
    eq(
        ctx4.performed,
        listOf("sleep:100", "sleep:200", "sleep:300", "sleep:400", "give-up"),
        "retry: backoff grows with the attempt",
    )

    val (state1, ctx1) = examples.retry.run(1)
    eq(state1, examples.retry.S.Exhausted, "retry: a single attempt gives up immediately")
    eq(ctx1.performed, listOf("sleep:100", "give-up"), "retry: no extra sleeps")

    val aborted = examples.retry.step(examples.retry.Impl(), examples.retry.Ctx(5), examples.retry.S.Waiting(2), examples.retry.A.Abort)
    eq(aborted, Step.Go(examples.retry.S.Exhausted), "retry: abort is static and needs no handler")
}

private fun session() {
    val m = examples.login.Impl()
    fun fresh() = examples.login.session.S.LoggedOut(examples.login.auth.S.AwaitingCredentials(0))

    eq(
        examples.login.session.step(m, examples.login.session.Ctx(examples.login.auth.Ctx(3)), fresh(), examples.login.session.A.Credentials(true)),
        Step.Go(examples.login.session.S.Active, emptyList()),
        "login: a good credential promotes the parent out of LoggedOut",
    )

    val bad = examples.login.session.step(m, examples.login.session.Ctx(examples.login.auth.Ctx(3)), fresh(), examples.login.session.A.Credentials(false))
    eq(
        bad.effects,
        listOf(examples.login.session.F.Redirect),
        "login: auth.Prompt became session.Redirect on the way up",
    )
    eq(
        (bad as Step.Go).next,
        examples.login.session.S.LoggedOut(examples.login.auth.S.AwaitingCredentials(1)),
        "login: a bad credential keeps the parent where it is",
    )

    eq(
        examples.login.session.step(m, examples.login.session.Ctx(examples.login.auth.Ctx(1)), fresh(), examples.login.session.A.Credentials(false)),
        Step.Go(examples.login.session.S.Banned, listOf(examples.login.session.F.Warn)),
        "login: exhausting the child bans the session",
    )

    eq(
        examples.login.auth.step(m, examples.login.auth.Ctx(2), examples.login.auth.S.AwaitingCredentials(0), examples.login.auth.A.Submit(true)),
        Step.Go(examples.login.auth.S.Authenticated, emptyList()),
        "login: the child is a machine in its own right",
    )

    eq(
        examples.login.session.TABLE.cell(0, 2),
        dev.tabula.Cell.Ignore,
        "login: coverage is not inherited silently",
    )
}

fun main() {
    trafficLight()
    timer()
    retry()
    session()

    if (failures == 0) println("ok   kotlin examples ($checks checks)")
    else println("FAIL kotlin examples ($failures of $checks checks failed)")
    if (failures > 0) kotlin.system.exitProcess(1)
}
