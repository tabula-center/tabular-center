import TabularCenter

// Every required member, uncolored. Must compile against the emitted timer:
// if it does not, the emitter's surface and the developer's have drifted.
final class CompleteTimer: TimerCells {
    func idleStart(_ ctx: Timer.Ctx) -> Step<Timer.S, Timer.F> {
        .go(.running(since: 0), effects: [.startClock])
    }

    func runningTick(_ ctx: Timer.Ctx, _ state: Timer.Running, _ action: Timer.Tick) -> Step<Timer.S, Timer.F> {
        action.now - state.since > 10 ? .go(.done, effects: [.note(text: "elapsed")]) : .stay(effects: [])
    }

    func startClock(_ ctx: Timer.Ctx) -> Timer.A? { nil }
    func stopClock(_ ctx: Timer.Ctx) -> Timer.A? { nil }
    func note(_ ctx: Timer.Ctx, _ effect: String) -> Timer.A? { nil }
    func halt(_ ctx: Timer.Ctx, _ effect: Timer.Reason) -> Timer.A? { nil }
}

func driveTimer() -> Timer.A? {
    let cells = CompleteTimer()
    let ctx = Timer.Ctx()
    let next = Timer.step(cells, ctx, .running(since: 0), .tick(now: 11))
    return next.effects.compactMap { Timer.perform(cells, ctx, $0) }.first
}
