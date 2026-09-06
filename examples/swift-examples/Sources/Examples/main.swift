import Tabula

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Tests for the four examples.
///
/// The same assertions as the Rust and Kotlin examples, deliberately: the three
/// implementations agreeing on worked examples is the same kind of check
/// `spec/conformance` performs on fixtures, and it is where the design findings
/// have come from.

enum Check {
    static var failures = 0
    static var checks = 0

    static func eq<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
        checks += 1
        if actual != expected {
            failures += 1
            print("FAIL \(what)")
            print("       got      \(actual)")
            print("       expected \(expected)")
        }
    }

    static func ok(_ condition: Bool, _ what: String) {
        checks += 1
        if !condition {
            failures += 1
            print("FAIL \(what)")
        }
    }
}

func trafficLight() {
    let ctx = TrafficLight.Ctx()
    let c = TrafficLight.Controller()
    var s = TrafficLight.S.red
    for _ in 0..<6 {
        s = TrafficLight.step(c, ctx, s, .advance).target ?? s
    }
    Check.eq(s, .red, "traffic light: two full cycles return to red")
    Check.eq(ctx.cycles, 2, "traffic light: context counted both cycles")

    for from in [TrafficLight.S.red, .green, .amber] {
        Check.eq(
            TrafficLight.step(c, TrafficLight.Ctx(), from, .fault).target, .red,
            "traffic light: fault from \(from) goes red")
    }

    let cov = TrafficLight.TABLE.coverage()
    Check.eq(cov.total, 6, "traffic light: six cells")
    Check.eq(cov.requiredMembers, 1, "traffic light: one implementation")
}

func timer() {
    let m = Timer.Impl()

    Check.eq(
        Timer.step(m, Timer.Ctx(limit: 10), .running(since: 0), .tick(now: 1)),
        .stay(effects: []),
        "timer: a tick below the limit stays")
    Check.ok(
        !Timer.step(m, Timer.Ctx(limit: 10), .running(since: 0), .tick(now: 1)).isIgnored,
        "timer: a tick while running is meaningful, not ignored")
    Check.eq(
        Timer.step(m, Timer.Ctx(limit: 3), .running(since: 2), .tick(now: 9)),
        .go(.done, effects: [.stopClock(reason: .elapsed)]),
        "timer: the limit finishes the timer")
    // The same effect, a different reason. The payload tells them apart.
    Check.eq(
        Timer.step(m, Timer.Ctx(limit: 100), .running(since: 0), .cancel).effects,
        [.stopClock(reason: .cancelled)],
        "timer: cancelling stops the clock for a different reason")

    let ctx = Timer.Ctx(limit: 1)
    _ = Timer.perform(m, ctx, .stopClock(reason: .elapsed))
    Check.eq(ctx.log, ["stop:elapsed"], "timer: effect handlers receive narrowed payloads")

    let inapplicable: [(Timer.S, Timer.A)] = [
        (.idle, .tick(now: 1)), (.idle, .cancel), (.done, .cancel),
    ]
    for (s, a) in inapplicable {
        Check.ok(
            Timer.step(m, Timer.Ctx(limit: 1), s, a).isIgnored,
            "timer: \(a) means nothing in \(s)")
    }
}

func retry() {
    do {
        let (state3, ctx3) = try Retry.run(maxAttempts: 3)
        Check.eq(state3, .exhausted, "retry: backs off and gives up on its own")
        Check.eq(
            ctx3.performed, ["sleep:100", "sleep:200", "sleep:300", "give-up"],
            "retry: one dispatch, four effects, all follow-ups through the mailbox")

        let (_, ctx4) = try Retry.run(maxAttempts: 4)
        Check.eq(
            ctx4.performed, ["sleep:100", "sleep:200", "sleep:300", "sleep:400", "give-up"],
            "retry: backoff grows with the attempt")

        let (state1, ctx1) = try Retry.run(maxAttempts: 1)
        Check.eq(state1, .exhausted, "retry: a single attempt gives up immediately")
        Check.eq(ctx1.performed, ["sleep:100", "give-up"], "retry: no extra sleeps")
    } catch {
        Check.ok(false, "retry: driver threw \(error)")
    }

    let aborted = Retry.step(
        Retry.Impl(), Retry.Ctx(maxAttempts: 5), .waiting(attempt: 2), .abort)
    Check.eq(aborted, .go(.exhausted, effects: []), "retry: abort is static, no handler needed")
}

func login() {
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

    // Coverage is not inherited silently: the LoggedOut row lists all three
    // columns, and one of them is not a delegate.
    Check.eq(SESSION_TABLE.cell(0, 2), .ignore, "login: coverage is not inherited silently")
}

trafficLight()
timer()
retry()
login()

if Check.failures == 0 {
    print("ok   swift examples (\(Check.checks) checks)")
} else {
    print("FAIL swift examples (\(Check.failures) of \(Check.checks) checks failed)")
    exit(1)
}
