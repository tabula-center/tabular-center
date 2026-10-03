// Checks for `Login.swift`, in their own file and their own build product.
//
// Swift's split is by *target* rather than by module: these live alongside the
// implementation rather than importing it, because the example types are not
// `public` and making them so would be a sweep across every example for the
// benefit of the harness rather than of a reader. Each example is still its
// own target with its own dependency line, built and run on its own.

import ExampleCheck
import TabularCenter

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

let m = LoginImpl()
func fresh() -> Session.S { .loggedOut(auth: .awaiting(attempts: 0)) }

Check.eq(
    sessionStep(m, Session.Ctx(auth: Auth.Ctx(maxAttempts: 3)), fresh(), .credentials(ok: true)),
    .go(.active, effects: []),
    "login: a good credential promotes the parent out of loggedOut")

let bad = sessionStep(
    m, Session.Ctx(auth: Auth.Ctx(maxAttempts: 3)), fresh(), .credentials(ok: false))
Check.eq(bad.effects, [.redirect], "login: auth.prompt became session.redirect on the way up")
Check.eq(
    bad.target, .loggedOut(auth: .awaiting(attempts: 1)),
    "login: a bad credential keeps the parent where it is")

Check.eq(
    sessionStep(
        m, Session.Ctx(auth: Auth.Ctx(maxAttempts: 1)), fresh(), .credentials(ok: false)),
    .go(.banned, effects: [.warn]),
    "login: exhausting the child bans the session")

Check.eq(
    authStep(m, Auth.Ctx(maxAttempts: 2), .awaiting(attempts: 0), .submit(ok: true)),
    .go(.authenticated, effects: []),
    "login: the child is a machine in its own right")

Check.eq(SESSION_TABLE.cell(0, 2), .ignore, "login: coverage is not inherited silently")

exit(Check.report("swift login"))
