//~ EXPECT: does not conform to protocol 'TimerCells'
//
// The guarantee, after generation. `runningTick` is a HANDLE cell, so the
// EMITTED protocol requires it; leaving it out must fail the build. Same claim
// as swift/compile_fail/missing_cell.swift, which checks the hand-written
// reference -- this one checks what the generator actually produces.
import Tabula

final class Incomplete: TimerCells {
    func idleStart(_ ctx: Ctx) -> Step<S, F> { .ignored }
    // runningTick is missing.
    func startClock(_ ctx: Ctx) -> A? { nil }
    func stopClock(_ ctx: Ctx) -> A? { nil }
    func note(_ ctx: Ctx, _ effect: String) -> A? { nil }
}
