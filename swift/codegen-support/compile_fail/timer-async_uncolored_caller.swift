//~ EXPECT: 'async' call in a function that does not support concurrency
//
// Color reaches the caller. The prototype is `async throws`, so the emitted
// `step` is too, and an uncolored function cannot drive it. This is the
// property ARCHITECTURE 5 states as "one matrix yields one color", and the one
// the emitter broke before it split effect specifiers from attributes: it
// wrote `async throws func step`, which is not Swift at all.
import Tabula

final class Cells: TimerAsyncCells {
    func idleStart(_ ctx: Ctx) async throws -> Step<S, F> { .ignored }
    func runningTick(_ ctx: Ctx, _ state: Running, _ action: Tick) async throws -> Step<S, F> { .ignored }
    func startClock(_ ctx: Ctx) async throws -> A? { nil }
    func stopClock(_ ctx: Ctx) async throws -> A? { nil }
    func note(_ ctx: Ctx, _ effect: String) async throws -> A? { nil }
}

// `throws` and `try`, so the one thing missing is `async`: the error this
// fixture expects is then the only one, rather than one of two.
func uncolored() throws -> Step<S, F> {
    try step(Cells(), Ctx(), .idle, .start)
}
