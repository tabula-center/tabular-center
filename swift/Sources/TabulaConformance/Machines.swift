import Tabula

/// The fixture machines, written in the shape the macro will generate.
///
/// Each is the Swift counterpart of a Rust adapter in `tabula-conformance` and
/// a Kotlin one in `conformance/`. The three agreeing on these fixtures is the
/// only thing keeping the implementations from drifting.

// MARK: - timer.tbl

enum TimerS: Equatable { case idle, running(since: Int), done }
enum TimerA: Equatable { case start, tick(now: Int), cancel }
enum TimerF: Equatable { case startClock, stopClock }

final class TimerCtx {
    let limit: Int
    init(limit: Int) { self.limit = limit }
}

struct TimerRunning { let since: Int }
struct TimerTick { let now: Int }

protocol TimerCells {
    func idleStart(_ ctx: TimerCtx) -> Step<TimerS, TimerF>
    func runningTick(_ ctx: TimerCtx, _ s: TimerRunning, _ a: TimerTick) -> Step<TimerS, TimerF>
}

func timerStep(_ c: TimerCells, _ ctx: TimerCtx, _ s: TimerS, _ a: TimerA) -> Step<TimerS, TimerF> {
    switch (s, a) {
    case (.idle, .start): return c.idleStart(ctx)
    case (.idle, .tick): return .ignored
    case (.idle, .cancel): return .ignored
    case (.running, .start): return .ignored
    case let (.running(since), .tick(now)):
        return c.runningTick(ctx, TimerRunning(since: since), TimerTick(now: now))
    case (.running, .cancel): return .go(.idle, effects: [.stopClock])
    case (.done, .start): return .go(.running(since: 0), effects: [.startClock])
    case (.done, .tick): return .ignored
    case (.done, .cancel): return .ignored
    }
}

let TIMER_TABLE = Table(
    machine: "Timer",
    states: ["Idle", "Running", "Done"],
    actions: ["Start", "Tick", "Cancel"],
    cells: [
        [.handle, .ignore, .ignore],
        [.ignore, .handle, .go(target: "Idle", effects: ["StopClock"])],
        [.go(target: "Running", effects: ["StartClock"]), .ignore, .ignore],
    ],
    initial: "Idle"
)

struct TimerImpl: TimerCells {
    func idleStart(_ ctx: TimerCtx) -> Step<TimerS, TimerF> {
        .go(.running(since: 0), effects: [.startClock])
    }
    func runningTick(
        _ ctx: TimerCtx, _ s: TimerRunning, _ a: TimerTick
    ) -> Step<TimerS, TimerF> {
        a.now - s.since >= ctx.limit
            ? .go(.done, effects: [.stopClock])
            : .stay(effects: [])
    }
}

// MARK: - toggle.tbl — the only coverage for EMIT and UNREACHABLE

enum ToggleS: Equatable { case off, on }
enum ToggleA: Equatable { case flip, poke, reset }
enum ToggleF: Equatable { case light, buzz }

struct ToggleCtx {}

protocol ToggleCells {
    func onPoke(_ ctx: ToggleCtx) -> Step<ToggleS, ToggleF>
}

func toggleStep(
    _ c: ToggleCells, _ ctx: ToggleCtx, _ s: ToggleS, _ a: ToggleA
) -> Step<ToggleS, ToggleF> {
    switch (s, a) {
    case (.off, .flip): return .go(.on, effects: [.light])
    case (.off, .poke): return .stay(effects: [.buzz])
    case (.off, .reset): return .ignored
    case (.on, .flip): return .go(.off, effects: [])
    case (.on, .poke): return c.onPoke(ctx)
    // UNREACHABLE compiles to a trap. Writing it *is* the implementation, so
    // it generates no member.
    case (.on, .reset):
        fatalError("tabula: On x Reset was declared UNREACHABLE but occurred")
    }
}

let TOGGLE_TABLE = Table(
    machine: "Toggle",
    states: ["Off", "On"],
    actions: ["Flip", "Poke", "Reset"],
    cells: [
        [.go(target: "On", effects: ["Light"]), .emit(effects: ["Buzz"]), .ignore],
        [.go(target: "Off", effects: []), .handle, .unreachable],
    ],
    initial: "Off"
)

struct ToggleImpl: ToggleCells {
    func onPoke(_ ctx: ToggleCtx) -> Step<ToggleS, ToggleF> { .stay(effects: []) }
}
