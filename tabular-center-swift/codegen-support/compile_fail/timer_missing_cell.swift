//~ EXPECT: does not conform to protocol 'TimerCells'
//
// The guarantee, after generation. `runningTick` is a HANDLE cell, so the
// EMITTED protocol requires it; leaving it out must fail the build. Same claim
// as tabular-center-swift/compile_fail/missing_cell.swift, which checks the hand-written
// reference -- this one checks what the generator actually produces.
import TabularCenter

final class Incomplete: TimerCells {
    func idleStart(_ ctx: Timer.Ctx) -> Step<Timer.S, Timer.F> { .ignored }
    func startClock(_ ctx: Timer.Ctx) -> Timer.A? { nil }
    func stopClock(_ ctx: Timer.Ctx) -> Timer.A? { nil }
    func note(_ ctx: Timer.Ctx, _ effect: String) -> Timer.A? { nil }
    func halt(_ ctx: Timer.Ctx, _ effect: Timer.Reason) -> Timer.A? { nil }
}
