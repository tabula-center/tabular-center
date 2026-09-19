import Tabula

// Every required member, uncolored. Must compile against the emitted
// `timer.swift`: if it does not, the emitter's surface and the developer's
// have drifted apart.
final class CompleteTimer: TimerCells {
    func idleStart(_ ctx: Ctx) -> Step<S, F> {
        .go(.running(since: 0), effects: [.startClock])
    }

    func runningTick(_ ctx: Ctx, _ state: Running, _ action: Tick) -> Step<S, F> {
        action.now - state.since > 10 ? .go(.done, effects: [.note(text: "elapsed")]) : .stay(effects: [])
    }

    func startClock(_ ctx: Ctx) -> A? { nil }
    func stopClock(_ ctx: Ctx) -> A? { nil }
    func note(_ ctx: Ctx, _ effect: String) -> A? { nil }
}

// The dispatcher and the effect pump are callable with it, uncolored.
func driveTimer() -> A? {
    let cells = CompleteTimer()
    let ctx = Ctx()
    let next = step(cells, ctx, .running(since: 0), .tick(now: 11))
    return next.effects.compactMap { perform(cells, ctx, $0) }.first
}
