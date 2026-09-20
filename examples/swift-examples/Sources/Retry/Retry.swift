import Tabula

/// **3. The driver, and why `step` is non-reentrant.**
///
/// The only example where an effect handler returns an action. The follow-up
/// goes onto the mailbox and is stepped on the next turn of the loop, rather
/// than recursing into `step` from inside a handler — which a handler is given
/// no way to do.
enum Retry {
    enum S: Equatable { case ready, waiting(attempt: Int), exhausted }
    enum A: Equatable { case attempt, elapsed, abort }
    enum F: Equatable { case sleep(ms: Int), giveUp }

    final class Ctx {
        let maxAttempts: Int
        /// Every effect the handler carried out, in order.
        var performed: [String] = []
        init(maxAttempts: Int) { self.maxAttempts = maxAttempts }
    }

    struct Waiting { let attempt: Int }

    protocol Cells {
        func readyAttempt(_ ctx: Ctx) -> Step<S, F>
        func waitingElapsed(_ ctx: Ctx, _ state: Waiting) -> Step<S, F>
        func sleep(_ ctx: Ctx, _ ms: Int) -> A?
        func giveUp(_ ctx: Ctx) -> A?
    }

    static func step(_ c: Cells, _ ctx: Ctx, _ s: S, _ a: A) -> Step<S, F> {
        switch (s, a) {
        case (.ready, .attempt): return c.readyAttempt(ctx)
        case (.ready, .elapsed): return .ignored
        case (.ready, .abort): return .go(.exhausted, effects: [])
        case (.waiting, .attempt): return .ignored
        case let (.waiting(attempt), .elapsed):
            return c.waitingElapsed(ctx, Waiting(attempt: attempt))
        case (.waiting, .abort): return .go(.exhausted, effects: [])
        case (.exhausted, .attempt): return .ignored
        case (.exhausted, .elapsed): return .ignored
        case (.exhausted, .abort): return .ignored
        }
    }

    static func perform(_ c: Cells, _ ctx: Ctx, _ f: F) -> A? {
        switch f {
        case let .sleep(ms): return c.sleep(ctx, ms)
        case .giveUp: return c.giveUp(ctx)
        }
    }

    struct Impl: Cells {
        func readyAttempt(_ ctx: Ctx) -> Step<S, F> {
            .go(.waiting(attempt: 1), effects: [.sleep(ms: 100)])
        }

        func waitingElapsed(_ ctx: Ctx, _ state: Waiting) -> Step<S, F> {
            if state.attempt >= ctx.maxAttempts {
                return .go(.exhausted, effects: [.giveUp])
            }
            let next = state.attempt + 1
            return .go(.waiting(attempt: next), effects: [.sleep(ms: 100 * next)])
        }

        /// Sleeping is what produces the next `elapsed`.
        ///
        /// Returned as **data**. The driver enqueues it; this function cannot
        /// reach `step` even if it wanted to.
        func sleep(_ ctx: Ctx, _ ms: Int) -> A? {
            ctx.performed.append("sleep:\(ms)")
            return .elapsed
        }

        func giveUp(_ ctx: Ctx) -> A? {
            ctx.performed.append("give-up")
            return nil
        }
    }

    /// Drive from `ready` until nothing is pending.
    static func run(maxAttempts: Int) throws -> (S, Ctx) {
        let ctx = Ctx(maxAttempts: maxAttempts)
        let cells = Impl()
        let driver = Driver<S, A, F>(initial: .ready)
        try driver.dispatch(
            .attempt,
            step: { s, a in step(cells, ctx, s, a) },
            perform: { f in perform(cells, ctx, f) }
        )
        return (driver.state, ctx)
    }
}
