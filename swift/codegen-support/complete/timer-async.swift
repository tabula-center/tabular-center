import Tabula

// Every required member, colored `async throws` as the prototype says.
final class CompleteTimerAsync: TimerAsyncCells {
    func idleStart(_ ctx: TimerAsync.Ctx) async throws -> Step<TimerAsync.S, TimerAsync.F> {
        .go(.running(since: 0), effects: [.startClock])
    }

    func runningTick(
        _ ctx: TimerAsync.Ctx, _ state: TimerAsync.Running, _ action: TimerAsync.Tick
    ) async throws -> Step<TimerAsync.S, TimerAsync.F> {
        .stay(effects: [])
    }

    func startClock(_ ctx: TimerAsync.Ctx) async throws -> TimerAsync.A? { nil }
    func stopClock(_ ctx: TimerAsync.Ctx) async throws -> TimerAsync.A? { nil }
    func note(_ ctx: TimerAsync.Ctx, _ effect: String) async throws -> TimerAsync.A? { nil }
    func halt(_ ctx: TimerAsync.Ctx, _ effect: Timer.Reason) async throws -> TimerAsync.A? { nil }
}

// The color reaches the caller: `step` and `perform` need `try await`.
func driveTimerAsync() async throws -> TimerAsync.A? {
    let cells = CompleteTimerAsync()
    let ctx = TimerAsync.Ctx()
    let next = try await TimerAsync.step(cells, ctx, .idle, .start)
    for f in next.effects {
        if let follow = try await TimerAsync.perform(cells, ctx, f) { return follow }
    }
    return nil
}
