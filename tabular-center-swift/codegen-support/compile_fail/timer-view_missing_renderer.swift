//~ EXPECT: does not conform to protocol 'TimerViewRenders'
//
// Builder mode keeps the guarantee: an associated type per state does not
// make a renderer optional. The cells are `CompleteTimerView`'s, verbatim, so
// the one conformance that can fail is `TimerViewRenders`.
import TabularCenter

final class BlankTimerView: TimerViewCells, TimerViewRenders {
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
}
