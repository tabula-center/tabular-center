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
/// `tabular-center::empty-emit`.
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

// MARK: - payload-hoist.tbl — the only coverage for `tabular-center::payload-hoist`

/// `attempt` in three states, which is what the lint is looking for.
///
/// The machine is deliberately a little wrong: a retry counter that outlives
/// every transition belongs in Context, and three states carrying their own
/// copy is the smell `tabular-center::payload-hoist` names. A fixture for a lint has
/// to trip it, so this models the smell rather than the fix.
///
/// Three is `payloadHoistStates` exactly. An implementation firing on `>`
/// rather than `>=` passes every other fixture and fails this one.
enum ConnS: Equatable {
    case connecting(attempt: Int)
    case backoff(attempt: Int)
    case reconnecting(attempt: Int)
    case live
}

enum ConnA: Equatable { case open, fail, timeout }

/// No effects, like `GateF`. Two fixtures now cover the uninhabited case; this
/// one reaches it with payload-carrying states, which `effects-never` does not.
enum ConnF {}

final class ConnCtx {
    let maxAttempts: Int
    init(maxAttempts: Int) { self.maxAttempts = maxAttempts }
}

struct ConnBackoff { let attempt: Int }

protocol ConnCells {
    func connectingOpen(_ ctx: ConnCtx) -> Step<ConnS, ConnF>
    func reconnectingOpen(_ ctx: ConnCtx) -> Step<ConnS, ConnF>
    func backoffTimeout(_ ctx: ConnCtx, _ s: ConnBackoff) -> Step<ConnS, ConnF>
}

func connStep(
    _ c: ConnCells, _ ctx: ConnCtx, _ s: ConnS, _ a: ConnA
) -> Step<ConnS, ConnF> {
    switch (s, a) {
    case (.connecting, .open): return c.connectingOpen(ctx)
    // A static cell cannot read the state it is leaving, so the counter
    // restarts here. That is what GO means, and it is half of why this machine
    // wants the field in Context.
    case (.connecting, .fail): return .go(.backoff(attempt: 0), effects: [])
    case (.connecting, .timeout): return .go(.backoff(attempt: 0), effects: [])
    case (.backoff, .open): return .ignored
    case (.backoff, .fail): return .ignored
    case let (.backoff(attempt), .timeout):
        return c.backoffTimeout(ctx, ConnBackoff(attempt: attempt))
    case (.reconnecting, .open): return c.reconnectingOpen(ctx)
    case (.reconnecting, .fail): return .go(.backoff(attempt: 0), effects: [])
    case (.reconnecting, .timeout): return .go(.backoff(attempt: 0), effects: [])
    case (.live, .open): return .ignored
    case (.live, .fail): return .go(.reconnecting(attempt: 0), effects: [])
    case (.live, .timeout): return .ignored
    }
}

let CONN_TABLE = Table(
    machine: "Conn",
    states: ["Connecting", "Backoff", "Reconnecting", "Live"],
    actions: ["Open", "Fail", "Timeout"],
    cells: [
        [.handle, .go(target: "Backoff", effects: []), .go(target: "Backoff", effects: [])],
        [.ignore, .ignore, .handle],
        [.handle, .go(target: "Backoff", effects: []), .go(target: "Backoff", effects: [])],
        [.ignore, .go(target: "Reconnecting", effects: []), .ignore],
    ],
    initial: "Connecting"
)

struct ConnImpl: ConnCells {
    func connectingOpen(_ ctx: ConnCtx) -> Step<ConnS, ConnF> { .go(.live, effects: []) }
    func reconnectingOpen(_ ctx: ConnCtx) -> Step<ConnS, ConnF> { .go(.live, effects: []) }

    /// The only cell that advances the counter, and the only one that can.
    func backoffTimeout(_ ctx: ConnCtx, _ s: ConnBackoff) -> Step<ConnS, ConnF> {
        s.attempt >= ctx.maxAttempts
            ? .stay(effects: [])
            : .go(.reconnecting(attempt: s.attempt + 1), effects: [])
    }
}

// MARK: - dead-column.tbl — the only coverage for `tabular-center::dead-column`

/// A vending machine whose refund button was never wired up.
///
/// `Refund` is `.ignored` in every row, which is the lint. The rest is shaped
/// to keep the other six quiet so the `.lint` golden holds exactly one line —
/// see the notes in the `.tbl`, including why 6 of 9 `IGNORE` (66%) sits
/// deliberately near `ignoreHeavyPercent` rather than comfortably below it.
enum VendS: Equatable {
    case idle
    case charged(credit: Int)
    case dispensing
}

enum VendA: Equatable { case insert, select, refund }

/// No effects, like `GateF` and `ConnF`.
enum VendF {}

final class VendCtx {
    let price: Int
    init(price: Int) { self.price = price }
}

struct VendCharged { let credit: Int }

protocol VendCells {
    func idleInsert(_ ctx: VendCtx) -> Step<VendS, VendF>
    func chargedSelect(_ ctx: VendCtx, _ s: VendCharged) -> Step<VendS, VendF>
}

func vendStep(
    _ c: VendCells, _ ctx: VendCtx, _ s: VendS, _ a: VendA
) -> Step<VendS, VendF> {
    switch (s, a) {
    case (.idle, .insert): return c.idleInsert(ctx)
    case (.idle, .select): return .ignored
    case (.idle, .refund): return .ignored
    case (.charged, .insert): return .ignored
    case let (.charged(credit), .select):
        return c.chargedSelect(ctx, VendCharged(credit: credit))
    case (.charged, .refund): return .ignored
    case (.dispensing, .insert): return .go(.idle, effects: [])
    case (.dispensing, .select): return .ignored
    case (.dispensing, .refund): return .ignored
    }
}

let VEND_TABLE = Table(
    machine: "Vend",
    states: ["Idle", "Charged", "Dispensing"],
    actions: ["Insert", "Select", "Refund"],
    cells: [
        [.handle, .ignore, .ignore],
        [.ignore, .handle, .ignore],
        [.go(target: "Idle", effects: []), .ignore, .ignore],
    ],
    initial: "Idle"
)

struct VendImpl: VendCells {
    func idleInsert(_ ctx: VendCtx) -> Step<VendS, VendF> {
        .go(.charged(credit: 1), effects: [])
    }

    /// `.stay`, not `.ignored`, when the credit is short. The distinction the
    /// third trace exists for: this cell is HANDLE and refuses, while
    /// `Charged`/`Insert` beside it is IGNORE and never runs.
    func chargedSelect(_ ctx: VendCtx, _ s: VendCharged) -> Step<VendS, VendF> {
        s.credit >= ctx.price ? .go(.dispensing, effects: []) : .stay(effects: [])
    }
}

// MARK: - ignore-heavy.tbl — the only coverage for `tabular-center::ignore-heavy`

/// Four states, each answering one action and ignoring the other four.
///
/// 15 of 20 cells `.ignore`, which is 75% against `ignoreHeavyPercent` (70).
/// 4x5 rather than the suite's usual 3x3 because the shape is forced: every row
/// and every column needs a live cell or `dead-row` / `dead-column` fire
/// instead, and three actions cannot get past 66%. See the `.tbl`.
///
/// No payloads, so `payload-hoist` cannot fire, and the `handle` cells make the
/// matrix not fully static, which gates `no-static-entry` off.
enum PollS: Equatable { case idle, armed, firing, spent }
enum PollA: Equatable { case arm, tick, fire, reset, abort }

/// No effects anywhere in the matrix, like `GateF`.
enum PollF {}

struct PollCtx {}

protocol PollCells {
    func idleArm(_ ctx: PollCtx) -> Step<PollS, PollF>
    func armedTick(_ ctx: PollCtx) -> Step<PollS, PollF>
    func firingFire(_ ctx: PollCtx) -> Step<PollS, PollF>
}

func pollStep(
    _ c: PollCells, _ ctx: PollCtx, _ s: PollS, _ a: PollA
) -> Step<PollS, PollF> {
    switch (s, a) {
    case (.idle, .arm): return c.idleArm(ctx)
    case (.idle, .tick): return .ignored
    case (.idle, .fire): return .ignored
    case (.idle, .reset): return .ignored
    case (.idle, .abort): return .ignored
    case (.armed, .arm): return .ignored
    case (.armed, .tick): return c.armedTick(ctx)
    case (.armed, .fire): return .ignored
    case (.armed, .reset): return .ignored
    case (.armed, .abort): return .go(.idle, effects: [])
    case (.firing, .arm): return .ignored
    case (.firing, .tick): return .ignored
    case (.firing, .fire): return c.firingFire(ctx)
    case (.firing, .reset): return .ignored
    case (.firing, .abort): return .ignored
    case (.spent, .arm): return .ignored
    case (.spent, .tick): return .ignored
    case (.spent, .fire): return .ignored
    case (.spent, .reset): return .go(.idle, effects: [])
    case (.spent, .abort): return .ignored
    }
}

let POLL_TABLE = Table(
    machine: "Poll",
    states: ["Idle", "Armed", "Firing", "Spent"],
    actions: ["Arm", "Tick", "Fire", "Reset", "Abort"],
    cells: [
        [.handle, .ignore, .ignore, .ignore, .ignore],
        [.ignore, .handle, .ignore, .ignore, .go(target: "Idle", effects: [])],
        [.ignore, .ignore, .handle, .ignore, .ignore],
        [.ignore, .ignore, .ignore, .go(target: "Idle", effects: []), .ignore],
    ],
    initial: "Idle"
)

struct PollImpl: PollCells {
    func idleArm(_ ctx: PollCtx) -> Step<PollS, PollF> { .go(.armed, effects: []) }

    /// `.stay`, not `.ignored`: the tick is handled and changes nothing.
    /// `one-action-per-state` asserts exactly that, one step after an
    /// `Arm => ignored` from the same state -- the two outcomes side by side.
    func armedTick(_ ctx: PollCtx) -> Step<PollS, PollF> { .stay(effects: []) }

    func firingFire(_ ctx: PollCtx) -> Step<PollS, PollF> { .go(.spent, effects: []) }
}

// MARK: - no-static-exit.tbl — the only coverage for `tabular-center::no-static-exit`

/// `Fault` can be entered and, as far as the matrix can prove, never left.
///
/// Its row is `[.ignore, .emit([Alarm]), .ignore]`. `EMIT` is `stay` plus an
/// effect, never a transition -- which is why it dispatches to `.stay` below
/// and not to `.go(.fault, ...)`. The `emit-stays-put` trace fails an
/// implementation that confuses the two.
///
/// That single `EMIT` is also what keeps `dead-row` from subsuming the lint:
/// `dead-row` needs every cell in the row to be `.ignore`.
enum BeaconS: Equatable { case idle, blinking, fault }
enum BeaconA: Equatable { case start, pulse, clear }
enum BeaconF: Equatable { case flash, alarm }

struct BeaconCtx {}

protocol BeaconCells {
    func idleStart(_ ctx: BeaconCtx) -> Step<BeaconS, BeaconF>
}

func beaconStep(
    _ c: BeaconCells, _ ctx: BeaconCtx, _ s: BeaconS, _ a: BeaconA
) -> Step<BeaconS, BeaconF> {
    switch (s, a) {
    case (.idle, .start): return c.idleStart(ctx)
    case (.idle, .pulse): return .ignored
    case (.idle, .clear): return .ignored
    case (.blinking, .start): return .ignored
    case (.blinking, .pulse): return .stay(effects: [.flash])
    case (.blinking, .clear): return .go(.idle, effects: [])
    case (.fault, .start): return .ignored
    case (.fault, .pulse): return .stay(effects: [.alarm])
    case (.fault, .clear): return .ignored
    }
}

let BEACON_TABLE = Table(
    machine: "Beacon",
    states: ["Idle", "Blinking", "Fault"],
    actions: ["Start", "Pulse", "Clear"],
    cells: [
        [.handle, .ignore, .ignore],
        [.ignore, .emit(effects: ["Flash"]), .go(target: "Idle", effects: [])],
        [.ignore, .emit(effects: ["Alarm"]), .ignore],
    ],
    initial: "Idle"
)

struct BeaconImpl: BeaconCells {
    /// The only dynamic cell, and the reason the matrix is not fully static --
    /// which is what keeps `no-static-entry` quiet about `Fault`, a state
    /// nothing in the matrix enters.
    func idleStart(_ ctx: BeaconCtx) -> Step<BeaconS, BeaconF> {
        .go(.blinking, effects: [])
    }
}

// MARK: - no-static-entry.tbl — the only coverage for `tabular-center::no-static-entry`

/// `Jammed` has a row and a way out, and nothing in the matrix leads in.
///
/// The matrix is **fully static** — no `handle`, `delegate` or `unreachable` —
/// which is the gate the lint needs before it may speak. `effects-never` pins
/// that gate shut; this pins it open. It is also why `DoorCells` has no
/// requirements: every cell is one word, and there is nothing to implement.
///
/// `Jammed`'s `EMIT(Thud)` dispatches to `.stay`, not to `.go(.jammed, ...)` —
/// a reachability walk that counted it as an incoming edge would go silent.
enum DoorS: Equatable { case closed, open, jammed }
enum DoorA: Equatable { case push, pull, kick }
enum DoorF: Equatable { case thud }

struct DoorCtx {}

/// Empty on purpose. The protocol still exists because the generated shape
/// always has one, and a fully static machine is that shape with no members.
protocol DoorCells {}

func doorStep(
    _ c: DoorCells, _ ctx: DoorCtx, _ s: DoorS, _ a: DoorA
) -> Step<DoorS, DoorF> {
    switch (s, a) {
    case (.closed, .push): return .go(.open, effects: [])
    case (.closed, .pull): return .ignored
    case (.closed, .kick): return .ignored
    case (.open, .push): return .ignored
    case (.open, .pull): return .go(.closed, effects: [])
    case (.open, .kick): return .ignored
    case (.jammed, .push): return .stay(effects: [.thud])
    case (.jammed, .pull): return .ignored
    case (.jammed, .kick): return .go(.closed, effects: [])
    }
}

let DOOR_TABLE = Table(
    machine: "Door",
    states: ["Closed", "Open", "Jammed"],
    actions: ["Push", "Pull", "Kick"],
    cells: [
        [.go(target: "Open", effects: []), .ignore, .ignore],
        [.ignore, .go(target: "Closed", effects: []), .ignore],
        [.emit(effects: ["Thud"]), .ignore, .go(target: "Closed", effects: [])],
    ],
    initial: "Closed"
)

struct DoorImpl: DoorCells {}

// MARK: - unreachable-heavy.tbl — the only coverage for `tabular-center::unreachable-heavy`

/// Three `unreachable` cells of twelve, which is `unreachableHeavyPercent`
/// exactly — on the boundary, so `>` in place of `>=` fails it.
///
/// `unreachable` generates no requirement and compiles to a trap with the
/// normative message from `spec/cells.md`, as in `toggleStep`. The traces
/// never reach one; the fixture's claim about them is carried by the table
/// and the goldens.
enum LinkS: Equatable { case down, dialing, up }
enum LinkA: Equatable { case dial, ack, hangup, ping }
enum LinkF: Equatable { case pong }

struct LinkCtx {
    let accept: Bool
}

protocol LinkCells {
    func dialingAck(_ ctx: LinkCtx) -> Step<LinkS, LinkF>
}

func linkStep(
    _ c: LinkCells, _ ctx: LinkCtx, _ s: LinkS, _ a: LinkA
) -> Step<LinkS, LinkF> {
    switch (s, a) {
    case (.down, .dial): return .go(.dialing, effects: [])
    case (.down, .ack):
        fatalError("tabula: Down x Ack was declared UNREACHABLE but occurred")
    case (.down, .hangup): return .ignored
    case (.down, .ping): return .ignored
    case (.dialing, .dial):
        fatalError("tabula: Dialing x Dial was declared UNREACHABLE but occurred")
    case (.dialing, .ack): return c.dialingAck(ctx)
    case (.dialing, .hangup): return .go(.down, effects: [])
    case (.dialing, .ping): return .ignored
    case (.up, .dial):
        fatalError("tabula: Up x Dial was declared UNREACHABLE but occurred")
    case (.up, .ack): return .ignored
    case (.up, .hangup): return .go(.down, effects: [])
    case (.up, .ping): return .stay(effects: [.pong])
    }
}

let LINK_TABLE = Table(
    machine: "Link",
    states: ["Down", "Dialing", "Up"],
    actions: ["Dial", "Ack", "Hangup", "Ping"],
    cells: [
        [.go(target: "Dialing", effects: []), .unreachable, .ignore, .ignore],
        [.unreachable, .handle, .go(target: "Down", effects: []), .ignore],
        [.unreachable, .ignore, .go(target: "Down", effects: []), .emit(effects: ["Pong"])],
    ],
    initial: "Down"
)

struct LinkImpl: LinkCells {
    /// `.stay`, not `.ignored`, when refused: the cell ran and chose not to move.
    func dialingAck(_ ctx: LinkCtx) -> Step<LinkS, LinkF> {
        ctx.accept ? .go(.up, effects: []) : .stay(effects: [])
    }
}
