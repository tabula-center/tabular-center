// The builder-mode twin, complete. Each renderer returns its own view type --
// `ViewishLabel` here, `some View` in SwiftUI -- and the protocol's associated
// types are inferred from them, as `View.Body` is. The builder attribute is
// inferred from the requirement too, so the bodies are single view
// expressions with no `return`, the way a SwiftUI `body` is written.
import TabularCenter

final class CompleteTimerView: TimerViewCells, TimerViewRenders {
    func idleStart(_ ctx: TimerView.Ctx) -> Step<TimerView.S, TimerView.F> {
        .go(.running(since: 0), effects: [.startClock])
    }

    func runningTick(
        _ ctx: TimerView.Ctx, _ state: TimerView.Running, _ action: TimerView.Tick
    ) -> Step<TimerView.S, TimerView.F> {
        .stay(effects: [])
    }

    func startClock(_ ctx: TimerView.Ctx) -> TimerView.A? { nil }
    func stopClock(_ ctx: TimerView.Ctx) -> TimerView.A? { nil }
    func note(_ ctx: TimerView.Ctx, _ effect: String) -> TimerView.A? { nil }
    func halt(_ ctx: TimerView.Ctx, _ effect: Timer.Reason) -> TimerView.A? { nil }

    func renderIdle() -> ViewishLabel { ViewishLabel(text: "idle") }
    func renderRunning(_ state: TimerView.Running) -> ViewishLabel { ViewishLabel(text: "running since \(state.since)") }
    func renderDone() -> ViewishLabel { ViewishLabel(text: "done") }
}

/// One opaque view for any state. Opaque result types need macOS 10.15 at
/// runtime, which the generated `render` declares; so does its caller.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
func viewForTimer() -> some Viewish {
    TimerView.render(CompleteTimerView(), .running(since: 3))
}
