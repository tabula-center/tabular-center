import Tabula

/// **4. Composition.**
///
/// A login session delegating its authentication to a child machine.
///
/// `protocol SessionCells: AuthCells` is the composition property in one line:
/// implementing the parent requires implementing the child, so a hole anywhere
/// in the child breaks any type conforming to the parent. Protocols are Swift's
/// trait bounds.

/// The child: authentication, written knowing nothing about sessions.
enum Auth {
    enum S: Equatable { case awaiting(attempts: Int), authenticated, lockedOut }
    enum A: Equatable { case submit(ok: Bool), reset }
    enum F: Equatable { case prompt, lockout }

    final class Ctx {
        let maxAttempts: Int
        init(maxAttempts: Int) { self.maxAttempts = maxAttempts }
    }

    struct Awaiting { let attempts: Int }
    struct Submit { let ok: Bool }
}

protocol AuthCells {
    func awaitingSubmit(_ ctx: Auth.Ctx, _ s: Auth.Awaiting, _ a: Auth.Submit) -> Step<Auth.S, Auth.F>
}

func authStep(_ c: AuthCells, _ ctx: Auth.Ctx, _ s: Auth.S, _ a: Auth.A) -> Step<Auth.S, Auth.F> {
    switch (s, a) {
    case let (.awaiting(attempts), .submit(ok)):
        return c.awaitingSubmit(ctx, Auth.Awaiting(attempts: attempts), Auth.Submit(ok: ok))
    case (.awaiting, .reset): return .go(.awaiting(attempts: 0), effects: [.prompt])
    case (.authenticated, .submit): return .ignored
    case (.authenticated, .reset): return .go(.awaiting(attempts: 0), effects: [.prompt])
    case (.lockedOut, .submit): return .ignored
    case (.lockedOut, .reset): return .ignored
    }
}

enum Session {
    enum S: Equatable { case loggedOut(auth: Auth.S), active, banned }
    enum A: Equatable { case credentials(ok: Bool), startOver, logout }
    enum F: Equatable { case audit, warn, redirect }

    /// The parent's context **contains** the child's, so `authChildCtx` is a
    /// field access and the child never sees session data it has no business
    /// with.
    final class Ctx {
        let auth: Auth.Ctx
        init(auth: Auth.Ctx) { self.auth = auth }
    }

    struct LoggedOut { let auth: Auth.S }
}

protocol SessionCells: AuthCells {
    func loggedOutCredentials(_ ctx: Session.Ctx, _ s: Session.LoggedOut, ok: Bool) -> Auth.A?
    func loggedOutStartOver(_ ctx: Session.Ctx, _ s: Session.LoggedOut) -> Auth.A?

    func authChildState(_ s: Session.LoggedOut) -> Auth.S
    func authEmbed(_ s: Session.LoggedOut, _ child: Auth.S) -> Session.S
    func authLift(_ effect: Auth.F) -> Session.F
    func authChildCtx(_ ctx: Session.Ctx) -> Auth.Ctx
}

func sessionStep(
    _ c: SessionCells, _ ctx: Session.Ctx, _ s: Session.S, _ a: Session.A
) -> Step<Session.S, Session.F> {
    switch (s, a) {
    case let (.loggedOut(auth), .credentials(ok)):
        let st = Session.LoggedOut(auth: auth)
        return delegate(c, ctx, st, c.loggedOutCredentials(ctx, st, ok: ok))
    case let (.loggedOut(auth), .startOver):
        let st = Session.LoggedOut(auth: auth)
        return delegate(c, ctx, st, c.loggedOutStartOver(ctx, st))
    case (.loggedOut, .logout): return .ignored
    case (.active, .credentials): return .ignored
    case (.active, .startOver): return .ignored
    case (.active, .logout): return .go(.banned, effects: [.audit])
    case (.banned, .credentials): return .ignored
    case (.banned, .startOver): return .ignored
    case (.banned, .logout): return .ignored
    }
}

/// A nil child action reports **ignored**, not stay: a parent action the
/// child's alphabet does not contain was not handled.
private func delegate(
    _ c: SessionCells, _ ctx: Session.Ctx, _ s: Session.LoggedOut, _ childAction: Auth.A?
) -> Step<Session.S, Session.F> {
    guard let childAction else { return .ignored }
    let childStep = authStep(c, c.authChildCtx(ctx), c.authChildState(s), childAction)
    let effects = childStep.effects.map(c.authLift)
    switch childStep {
    case let .go(next, _): return .go(c.authEmbed(s, next), effects: effects)
    case .stay: return .stay(effects: effects)
    case .ignored: return .ignored
    }
}

let SESSION_TABLE = Table(
    machine: "Session",
    states: ["LoggedOut", "Active", "Banned"],
    actions: ["Credentials", "StartOver", "Logout"],
    cells: [
        [.delegate(child: "auth"), .delegate(child: "auth"), .ignore],
        [.ignore, .ignore, .go(target: "Banned", effects: ["Audit"])],
        [.ignore, .ignore, .ignore],
    ],
    initial: "LoggedOut"
)

/// One type satisfying both machines' surfaces.
struct LoginImpl: SessionCells {
    func awaitingSubmit(
        _ ctx: Auth.Ctx, _ s: Auth.Awaiting, _ a: Auth.Submit
    ) -> Step<Auth.S, Auth.F> {
        if a.ok { return .go(.authenticated, effects: []) }
        if s.attempts + 1 >= ctx.maxAttempts { return .go(.lockedOut, effects: [.lockout]) }
        return .go(.awaiting(attempts: s.attempts + 1), effects: [.prompt])
    }

    func loggedOutCredentials(_ ctx: Session.Ctx, _ s: Session.LoggedOut, ok: Bool) -> Auth.A? {
        .submit(ok: ok)
    }

    func loggedOutStartOver(_ ctx: Session.Ctx, _ s: Session.LoggedOut) -> Auth.A? { .reset }

    func authChildState(_ s: Session.LoggedOut) -> Auth.S { s.auth }

    /// A child transition can be a parent transition.
    func authEmbed(_ s: Session.LoggedOut, _ child: Auth.S) -> Session.S {
        switch child {
        case .authenticated: return .active
        case .lockedOut: return .banned
        case .awaiting: return .loggedOut(auth: child)
        }
    }

    func authLift(_ effect: Auth.F) -> Session.F {
        switch effect {
        case .prompt: return .redirect
        case .lockout: return .warn
        }
    }

    func authChildCtx(_ ctx: Session.Ctx) -> Auth.Ctx { ctx.auth }
}
