import Tabula

// Every required member, colored `async throws` as the prototype says.
final class CompleteTimerAsync: TimerAsyncCells {
    func idleStart(_ ctx: Ctx) async throws -> Step<S, F> {
        .go(.running(since: 0), effects: [.startClock])
    }

    func runningTick(_ ctx: Ctx, _ state: Running, _ action: Tick) async throws -> Step<S, F> {
        .stay(effects: [])
    }

    func startClock(_ ctx: Ctx) async throws -> A? { nil }
    func stopClock(_ ctx: Ctx) async throws -> A? { nil }
    func note(_ ctx: Ctx, _ effect: String) async throws -> A? { nil }
}

// The color reaches the caller: `step` and `perform` need `try await`.
func driveTimerAsync() async throws -> A? {
    let cells = CompleteTimerAsync()
    let ctx = Ctx()
    let next = try await step(cells, ctx, .idle, .start)
    for f in next.effects {
        if let follow = try await perform(cells, ctx, f) { return follow }
    }
    return nil
}
