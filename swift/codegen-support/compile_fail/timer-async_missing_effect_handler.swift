//~ EXPECT: does not conform to protocol 'TimerAsyncCells'
//
// One required member per effect variant, colored like every other. `note`
// carries a payload and is named by no static cell -- the handler exists only
// because the effect does, and omitting it must fail the build.
import Tabula

final class Incomplete: TimerAsyncCells {
    func idleStart(_ ctx: Ctx) async throws -> Step<S, F> { .ignored }
    func runningTick(_ ctx: Ctx, _ state: Running, _ action: Tick) async throws -> Step<S, F> { .ignored }
    func startClock(_ ctx: Ctx) async throws -> A? { nil }
    func stopClock(_ ctx: Ctx) async throws -> A? { nil }
    // note is missing.
}
