import Tabula

/// **2. Payloads and effects.**
///
/// Payloads on both a state and an action, which is what makes narrowed cell
/// arguments worth having: `runningTick` receives `Running` and `Tick` as
/// concrete types, so `state.since` and `action.now` are plain fields.
enum Timer {
    enum S: Equatable { case idle, running(since: Int), done }
    enum A: Equatable { case start, tick(now: Int), cancel }

    /// Why a clock stopped. `stopClock` is emitted from two different places.
    enum Reason: Equatable { case cancelled, elapsed }

    enum F: Equatable { case startClock, stopClock(reason: Reason) }

    final class Ctx {
        let limit: Int
        var log: [String] = []
        init(limit: Int) { self.limit = limit }
    }

    struct Running { let since: Int }
    struct Tick { let now: Int }

    protocol Cells {
        func idleStart(_ ctx: Ctx) -> Step<S, F>
        func runningTick(_ ctx: Ctx, _ state: Running, _ action: Tick) -> Step<S, F>
        func startClock(_ ctx: Ctx) -> A?
        func stopClock(_ ctx: Ctx, _ reason: Reason) -> A?
    }

    static func step(_ c: Cells, _ ctx: Ctx, _ s: S, _ a: A) -> Step<S, F> {
        switch (s, a) {
        case (.idle, .start): return c.idleStart(ctx)
        case (.idle, .tick): return .ignored
        case (.idle, .cancel): return .ignored
        case (.running, .start): return .ignored
        case let (.running(since), .tick(now)):
            return c.runningTick(ctx, Running(since: since), Tick(now: now))
        case (.running, .cancel):
            return .go(.idle, effects: [.stopClock(reason: .cancelled)])
        case (.done, .start): return .go(.running(since: 0), effects: [.startClock])
        case (.done, .tick): return .ignored
        case (.done, .cancel): return .ignored
        }
    }

    static func perform(_ c: Cells, _ ctx: Ctx, _ f: F) -> A? {
        switch f {
        case .startClock: return c.startClock(ctx)
        case let .stopClock(reason): return c.stopClock(ctx, reason)
        }
    }

    static let TABLE = Table(
        machine: "Timer",
        states: ["Idle", "Running", "Done"],
        actions: ["Start", "Tick", "Cancel"],
        cells: [
            [.handle, .ignore, .ignore],
            [.ignore, .handle, .go(target: "Idle", effects: ["StopClock"])],
            [.go(target: "Running", effects: ["StartClock"]), .ignore, .ignore],
        ],
        initial: "Idle"
    )

    struct Impl: Cells {
        func idleStart(_ ctx: Ctx) -> Step<S, F> {
            .go(.running(since: 0), effects: [.startClock])
        }

        func runningTick(_ ctx: Ctx, _ state: Running, _ action: Tick) -> Step<S, F> {
            // No `if case`, no cast, no force-unwrap: the dispatcher matched.
            if action.now - state.since >= ctx.limit {
                return .go(.done, effects: [.stopClock(reason: .elapsed)])
            }
            // Handled, and staying put. Distinct from `.ignored`, which would
            // claim a tick is meaningless while running.
            return .stay(effects: [])
        }

        func startClock(_ ctx: Ctx) -> A? {
            ctx.log.append("start")
            return nil
        }

        func stopClock(_ ctx: Ctx, _ reason: Reason) -> A? {
            ctx.log.append("stop:\(reason)")
            return nil
        }
    }
}
