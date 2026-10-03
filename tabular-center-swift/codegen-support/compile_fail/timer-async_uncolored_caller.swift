//~ EXPECT: 'async' call in a function that does not support concurrency
//
// Color reaches the caller. The prototype is `async throws`, so the emitted
// `step` is too, and an uncolored function cannot drive it. This is the
// property ARCHITECTURE 5 states as "one matrix yields one color", and the one
// the emitter broke before it split effect specifiers from attributes: it
// wrote `async throws func step`, which is not Swift at all.
import TabularCenter

final class Cells: TimerAsyncCells {
    func idleStart(_ ctx: TimerAsync.Ctx) async throws -> Step<TimerAsync.S, TimerAsync.F> { .ignored }
    func runningTick(
        _ ctx: TimerAsync.Ctx, _ state: TimerAsync.Running, _ action: TimerAsync.Tick
    ) async throws -> Step<TimerAsync.S, TimerAsync.F> { .ignored }
    func startClock(_ ctx: TimerAsync.Ctx) async throws -> TimerAsync.A? { nil }
    func stopClock(_ ctx: TimerAsync.Ctx) async throws -> TimerAsync.A? { nil }
    func note(_ ctx: TimerAsync.Ctx, _ effect: String) async throws -> TimerAsync.A? { nil }
    func halt(_ ctx: TimerAsync.Ctx, _ effect: Timer.Reason) async throws -> TimerAsync.A? { nil }
}

func uncolored() throws -> Step<TimerAsync.S, TimerAsync.F> {
    try TimerAsync.step(Cells(), TimerAsync.Ctx(), .idle, .start)
}
