//~ EXPECT: does not conform to protocol 'TimerAsyncCells'
//
// One required member per effect variant, colored like every other. `note`
// carries a payload and is named by no static cell -- the handler exists only
// because the effect does, and omitting it must fail the build.
import Tabula

final class Incomplete: TimerAsyncCells {
    func idleStart(_ ctx: TimerAsync.Ctx) async throws -> Step<TimerAsync.S, TimerAsync.F> { .ignored }
    func runningTick(
        _ ctx: TimerAsync.Ctx, _ state: TimerAsync.Running, _ action: TimerAsync.Tick
    ) async throws -> Step<TimerAsync.S, TimerAsync.F> { .ignored }
    func startClock(_ ctx: TimerAsync.Ctx) async throws -> TimerAsync.A? { nil }
    func stopClock(_ ctx: TimerAsync.Ctx) async throws -> TimerAsync.A? { nil }
    // note is missing.
}
