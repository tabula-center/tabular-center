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

// MARK: - effects-never

/// A machine with an uninhabited effect enum.
///
/// A caseless enum is Swift's `effects F { }`: nothing can ever construct a
/// `GateF`. What makes it worth a fixture is what it removes -- with no effect
/// to name, `EMIT` cannot be written at all, because an empty one is
/// `tabula::empty-emit`.
///
/// `Step` puts no constraint on its effect type, so no conformance is needed
/// here and none is declared. An `Equatable` conformance would have to be
/// written by hand as `switch lhs {}`, and it would be proving nothing.
enum GateS: Equatable { case locked, open }
enum GateA: Equatable { case unlock, lock, push }
enum GateF {}

struct GateCtx {}

protocol GateCells {
    func onUnlock(_ ctx: GateCtx) -> Step<GateS, GateF>
    func onPush(_ ctx: GateCtx) -> Step<GateS, GateF>
}

func gateStep(
    _ c: GateCells, _ ctx: GateCtx, _ s: GateS, _ a: GateA
) -> Step<GateS, GateF> {
    switch (s, a) {
    case (.locked, .unlock): return c.onUnlock(ctx)
    case (.locked, .lock): return .ignored
    case (.locked, .push): return .ignored
    case (.open, .unlock): return .ignored
    case (.open, .lock): return .go(.locked, effects: [])
    case (.open, .push): return c.onPush(ctx)
    }
}

let GATE_TABLE = Table(
    machine: "Gate",
    states: ["Locked", "Open"],
    actions: ["Unlock", "Lock", "Push"],
    cells: [
        [.handle, .ignore, .ignore],
        [.ignore, .go(target: "Locked", effects: []), .handle],
    ],
    initial: "Locked"
)

struct GateImpl: GateCells {
    /// The only route into `Open`, and deliberately dynamic: a statically
    /// resolvable transition here would make the matrix fully static and
    /// defeat the reachability gate this fixture pins.
    func onUnlock(_ ctx: GateCtx) -> Step<GateS, GateF> { .go(.open, effects: []) }
    func onPush(_ ctx: GateCtx) -> Step<GateS, GateF> { .stay(effects: []) }
}
