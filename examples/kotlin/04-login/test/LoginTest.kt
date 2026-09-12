// Tests for `../src/Login.kt`, compiled as their own unit against the example's
// output rather than alongside it -- the Kotlin equivalent of a `tests/`
// directory. An example is read as a template, and a template should not show
// its tests living inside the implementation.

import dev.tabula.Step

fun main() {
    val m = examples.login.Impl()
    fun fresh() = examples.login.session.S.LoggedOut(examples.login.auth.S.AwaitingCredentials(0))

    Check.eq(
        examples.login.session.step(m, examples.login.session.Ctx(examples.login.auth.Ctx(3)), fresh(), examples.login.session.A.Credentials(true)),
        Step.Go(examples.login.session.S.Active, emptyList()),
        "login: a good credential promotes the parent out of LoggedOut",
    )

    val bad = examples.login.session.step(m, examples.login.session.Ctx(examples.login.auth.Ctx(3)), fresh(), examples.login.session.A.Credentials(false))
    Check.eq(
        bad.effects,
        listOf(examples.login.session.F.Redirect),
        "login: auth.Prompt became session.Redirect on the way up",
    )
    Check.eq(
        (bad as Step.Go).next,
        examples.login.session.S.LoggedOut(examples.login.auth.S.AwaitingCredentials(1)),
        "login: a bad credential keeps the parent where it is",
    )

    Check.eq(
        examples.login.session.step(m, examples.login.session.Ctx(examples.login.auth.Ctx(1)), fresh(), examples.login.session.A.Credentials(false)),
        Step.Go(examples.login.session.S.Banned, listOf(examples.login.session.F.Warn)),
        "login: exhausting the child bans the session",
    )

    Check.eq(
        examples.login.auth.step(m, examples.login.auth.Ctx(2), examples.login.auth.S.AwaitingCredentials(0), examples.login.auth.A.Submit(true)),
        Step.Go(examples.login.auth.S.Authenticated, emptyList()),
        "login: the child is a machine in its own right",
    )

    Check.eq(
        examples.login.session.TABLE.cell(0, 2),
        dev.tabula.Cell.Ignore,
        "login: coverage is not inherited silently",
    )

    Check.report("kotlin login")
}
