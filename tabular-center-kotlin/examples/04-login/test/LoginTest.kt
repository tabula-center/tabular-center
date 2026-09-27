// Tests for `../src/Login.kt`, compiled as their own unit against the
// example's output rather than alongside it -- the Kotlin equivalent of a
// `tests/` directory. A test in the same unit can reach anything, so it
// never shows that the example's own surface is usable.

import dev.tabularcenter.Step
import examples.login.*

fun main() {
    val m = Impl()
    fun fresh() = session.S.LoggedOut(auth.S.AwaitingCredentials(0))

    Check.eq(
        session.step(m, session.Ctx(auth.Ctx(3)), fresh(), session.A.Credentials(true)),
        Step.Go(session.S.Active, emptyList()),
        "login: a good credential promotes the parent out of LoggedOut",
    )

    val bad = session.step(m, session.Ctx(auth.Ctx(3)), fresh(), session.A.Credentials(false))
    Check.eq(
        bad.effects,
        listOf(session.F.Redirect),
        "login: auth.Prompt became session.Redirect on the way up",
    )
    Check.eq(
        (bad as Step.Go).next,
        session.S.LoggedOut(auth.S.AwaitingCredentials(1)),
        "login: a bad credential keeps the parent where it is",
    )

    Check.eq(
        session.step(m, session.Ctx(auth.Ctx(1)), fresh(), session.A.Credentials(false)),
        Step.Go(session.S.Banned, listOf(session.F.Warn)),
        "login: exhausting the child bans the session",
    )

    Check.eq(
        auth.step(m, auth.Ctx(2), auth.S.AwaitingCredentials(0), auth.A.Submit(true)),
        Step.Go(auth.S.Authenticated, emptyList()),
        "login: the child is a machine in its own right",
    )

    Check.eq(
        session.TABLE.cell(0, 2),
        dev.tabularcenter.Cell.Ignore,
        "login: coverage is not inherited silently",
    )

    Check.report("kotlin login")
}
