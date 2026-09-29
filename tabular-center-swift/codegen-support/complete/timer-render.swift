// The rendering twin, complete: every cell, every effect, every state's
// renderer. The cells are `CompleteTimerAsync`'s -- `async throws`, since the
// transition prototype is -- and the renderers are plain, since the rendering
// prototype is not. `renderRunning` receives `Running`, narrowed, and reads
// `since` with no pattern match.
import TabularCenter

final class CompleteTimerRender: TimerRenderCells, TimerRenderRenders {
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
    func renderDone() -> String { "done" }
}

/// Rendering is synchronous even though stepping is not: no `await` here.
func describeTimerRender() -> String {
    TimerRender.render(CompleteTimerRender(), .running(since: 3))
}
