//~ EXPECT: does not conform to protocol 'TimerRenderRenders'
//
// The rendering surface has the cells' guarantee: one required member per
// state, and a state with no renderer does not compile. The cells below are
// complete -- `CompleteTimerRender`'s, verbatim -- so the one conformance that
// can fail is `TimerRenderRenders`, and the EXPECT names it: a hole in the
// cells would name `TimerRenderCells` instead and not match.
import TabularCenter

final class BlankTimerRender: TimerRenderCells, TimerRenderRenders {
    func idleStart(_ ctx: TimerRender.Ctx) async throws -> Step<TimerRender.S, TimerRender.F> {
        .go(.running(since: 0), effects: [.startClock])
    }

    func runningTick(
        _ ctx: TimerRender.Ctx, _ state: TimerRender.Running, _ action: TimerRender.Tick
    ) async throws -> Step<TimerRender.S, TimerRender.F> {
        .stay(effects: [])
    }

    func startClock(_ ctx: TimerRender.Ctx) async throws -> TimerRender.A? { nil }
    func stopClock(_ ctx: TimerRender.Ctx) async throws -> TimerRender.A? { nil }
    func note(_ ctx: TimerRender.Ctx, _ effect: String) async throws -> TimerRender.A? { nil }
    func halt(_ ctx: TimerRender.Ctx, _ effect: Timer.Reason) async throws -> TimerRender.A? { nil }

    func renderIdle() -> String { "idle" }
    func renderRunning(_ state: TimerRender.Running) -> String { "running since \(state.since)" }

    // renderDone is missing.
}
