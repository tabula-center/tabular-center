import Foundation
import TabularCenter
import TabularCenterTesting

/// Runs the shared `spec/conformance` fixtures against the Swift
/// implementation.
///
/// Three things are compared, and the third only exists because there are three
/// implementations:
///
/// 1. The generated table, cell by cell.
/// 2. Traces: outcomes and effects, step by step.
/// 3. Nothing else here: the renderings (`.grid`, `.mmd`, `.lint`, `.cov`) are
///    written out with `--emit=<dir>` and diffed against the other two
///    implementations' by `tools/verify renderings-agree`, rather than each
///    being compared against a committed copy of one implementation's output.
///
/// Foundation is imported here and nowhere in `TabularCenterTesting`: the runner needs
/// file IO, and a published library should not put Foundation on every
/// consumer's link line to trim a string.

/// Outcome of one replayed step, in fixture vocabulary.
struct Observed {
    let expect: Expect
    let effects: [String]
}

/// Binds one fixture to one real machine.
protocol Adapter {
    var name: String { get }
    var table: Table { get }

    /// Payload fields, as `(state, field, type)`.
    ///
    /// Separate from `table` because only `tabular-center::payload-hoist` needs it.
    /// Rust has passed its `PAYLOADS` to the lint since the lint existed; this
    /// side took the empty default, so the two agreed only because no fixture
    /// had a field repeated often enough to fire.
    ///
    /// `type` is spelled in the implementation's own language. See
    /// `spec/diagnostics.md`.
    var payloads: Payloads { get }

    func replay(_ trace: Trace) throws -> [Observed]
}

extension Adapter {
    var payloads: Payloads { [] }
}

struct TimerAdapter: Adapter {
    let name = "timer"
    let table = TIMER_TABLE
    let payloads: Payloads = [(state: "Running", field: "since", type: "Int")]

    func replay(_ trace: Trace) throws -> [Observed] {
        let ctx = TimerCtx(limit: trace.ctx["limit"] ?? 0)
        let cells = TimerImpl()
        var state = try stateOf(trace.from, trace.fromFields)
        var out: [Observed] = []

        for st in trace.steps {
            let step = timerStep(cells, ctx, state, try actionOf(st.action, st.args))
            let effects = step.effects.map(Self.effectName)
            let expect: Expect
            switch step {
            case .stay: expect = .stay
            case .ignored: expect = .ignored
            case let .go(next, _):
                state = next
                var want: [String: Int] = [:]
                if case let .go(_, fields) = st.expect { want = fields }
                expect = describe(next, want)
            }
            out.append(Observed(expect: expect, effects: effects))
        }
        return out
    }

    /// Effect names as the *fixtures* spell them.
    ///
    /// Swift enum cases are lowerCamel — `stopClock` — while the shared
    /// fixtures use the variant names the other two languages generate,
    /// `StopClock`. String interpolation therefore does not agree with them,
    /// and `lastSegment` cannot fix a case difference without also hiding real
    /// drift. Naming them here keeps the comparison exact.
    static func effectName(_ f: TimerF) -> String {
        switch f {
        case .startClock: return "StartClock"
        case .stopClock: return "StopClock"
        }
    }

    private func stateOf(_ name: String, _ f: [String: Int]) throws -> TimerS {
        switch name {
        case "Idle": return .idle
        case "Done": return .done
        case "Running": return .running(since: f["since"] ?? 0)
        default: throw SpecError("timer: unknown state `\(name)`")
        }
    }

    private func actionOf(_ name: String, _ a: [String: Int]) throws -> TimerA {
        switch name {
        case "Start": return .start
        case "Cancel": return .cancel
        case "Tick": return .tick(now: a["now"] ?? 0)
        default: throw SpecError("timer: unknown action `\(name)`")
        }
    }

    private func describe(_ s: TimerS, _ want: [String: Int]) -> Expect {
        switch s {
        case .idle: return .go(state: "Idle", fields: [:])
        case .done: return .go(state: "Done", fields: [:])
        case let .running(since):
            return .go(state: "Running", fields: want["since"] != nil ? ["since": since] : [:])
        }
    }
}

struct ToggleAdapter: Adapter {
    let name = "toggle"
    let table = TOGGLE_TABLE

    /// See `TimerAdapter.effectName`.
    static func effectName(_ f: ToggleF) -> String {
        switch f {
        case .light: return "Light"
        case .buzz: return "Buzz"
        }
    }

    func replay(_ trace: Trace) throws -> [Observed] {
        let cells = ToggleImpl()
        var state: ToggleS
        switch trace.from {
        case "Off": state = .off
        case "On": state = .on
        default: throw SpecError("toggle: unknown state `\(trace.from)`")
        }

        var out: [Observed] = []
        for st in trace.steps {
            let action: ToggleA
            switch st.action {
            case "Flip": action = .flip
            case "Poke": action = .poke
            case "Reset": action = .reset
            default: throw SpecError("toggle: unknown action `\(st.action)`")
            }
            let step = toggleStep(cells, ToggleCtx(), state, action)
            let effects = step.effects.map(Self.effectName)
            let expect: Expect
            switch step {
            case .stay: expect = .stay
            case .ignored: expect = .ignored
            case let .go(next, _):
                state = next
                expect = .go(state: next == .off ? "Off" : "On", fields: [:])
            }
            out.append(Observed(expect: expect, effects: effects))
        }
        return out
    }
}

struct EffectsNeverAdapter: Adapter {
    let name = "effects-never"
    let table = GATE_TABLE

    func replay(_ trace: Trace) throws -> [Observed] {
        let cells = GateImpl()
        var state: GateS
        switch trace.from {
        case "Locked": state = .locked
        case "Open": state = .open
        default: throw SpecError("effects-never: unknown state `\(trace.from)`")
        }

        var out: [Observed] = []
        for st in trace.steps {
            let action: GateA
            switch st.action {
            case "Unlock": action = .unlock
            case "Lock": action = .lock
            case "Push": action = .push
            default: throw SpecError("effects-never: unknown action `\(st.action)`")
            }
            let step = gateStep(cells, GateCtx(), state, action)
            // Always empty, and the compiler says so out loud: mapping over
            // these produced `warning: will never be executed`, because GateF
            // is an enum with no cases and nothing can construct one.
            //
            // The map was there to run the same code path as every other
            // adapter rather than short-circuit it. That argument does not
            // survive the compiler proving the path unreachable -- an
            // unreachable path is not a path -- so take its word and leave the
            // uninhabited type to say what it means.
            let effects: [String] = []
            let expect: Expect
            switch step {
            case .stay: expect = .stay
            case .ignored: expect = .ignored
            case let .go(next, _):
                state = next
                expect = .go(state: next == .locked ? "Locked" : "Open", fields: [:])
            }
            out.append(Observed(expect: expect, effects: effects))
        }
        return out
    }
}

struct PayloadHoistAdapter: Adapter {
    let name = "payload-hoist"
    let table = CONN_TABLE

    /// Spelled `Int`, not `int`.
    ///
    /// The adapter reports its own language's type and `canonicalType` maps it
    /// onto the spec vocabulary before the comparison. Rust records `u32` and
    /// Kotlin `Long` for this same field; all three land on `attempt: int` and
    /// share one `.lint` golden. Writing `int` here would pass today and hide
    /// the mapping the fixture exists to exercise.
    let payloads: Payloads = [
        (state: "Connecting", field: "attempt", type: "Int"),
        (state: "Backoff", field: "attempt", type: "Int"),
        (state: "Reconnecting", field: "attempt", type: "Int"),
    ]

    func replay(_ trace: Trace) throws -> [Observed] {
        let ctx = ConnCtx(maxAttempts: trace.ctx["max_attempts"] ?? 0)
        let cells = ConnImpl()
        var state = try stateOf(trace.from, trace.fromFields)
        var out: [Observed] = []

        for st in trace.steps {
            let step = connStep(cells, ctx, state, try actionOf(st.action))
            // Always empty: `ConnF` has no cases, so nothing can construct one.
            // Written as a literal rather than a map for the reason spelled
            // out in EffectsNeverAdapter -- the compiler proves the map body
            // unreachable and says so.
            let effects: [String] = []
            let expect: Expect
            switch step {
            case .stay: expect = .stay
            case .ignored: expect = .ignored
            case let .go(next, _):
                state = next
                var want: [String: Int] = [:]
                if case let .go(_, fields) = st.expect { want = fields }
                expect = describe(next, want)
            }
            out.append(Observed(expect: expect, effects: effects))
        }
        return out
    }

    private func stateOf(_ name: String, _ f: [String: Int]) throws -> ConnS {
        let attempt = f["attempt"] ?? 0
        switch name {
        case "Connecting": return .connecting(attempt: attempt)
        case "Backoff": return .backoff(attempt: attempt)
        case "Reconnecting": return .reconnecting(attempt: attempt)
        case "Live": return .live
        default: throw SpecError("payload-hoist: unknown state `\(name)`")
        }
    }

    private func actionOf(_ name: String) throws -> ConnA {
        switch name {
        case "Open": return .open
        case "Fail": return .fail
        case "Timeout": return .timeout
        default: throw SpecError("payload-hoist: unknown action `\(name)`")
        }
    }

    private func describe(_ s: ConnS, _ want: [String: Int]) -> Expect {
        func fields(_ a: Int) -> [String: Int] {
            want["attempt"] != nil ? ["attempt": a] : [:]
        }
        switch s {
        case let .connecting(attempt): return .go(state: "Connecting", fields: fields(attempt))
        case let .backoff(attempt): return .go(state: "Backoff", fields: fields(attempt))
        case let .reconnecting(attempt):
            return .go(state: "Reconnecting", fields: fields(attempt))
        case .live: return .go(state: "Live", fields: [:])
        }
    }
}

struct DeadColumnAdapter: Adapter {
    let name = "dead-column"
    let table = VEND_TABLE

    /// One state, so `payload-hoist` stays out of this fixture's way. Spelled
    /// `Int`; Kotlin says `Long` and Rust `u32`, and all three canonicalise to
    /// `int` for the shared `.lint` golden.
    let payloads: Payloads = [
        (state: "Charged", field: "credit", type: "Int")
    ]

    func replay(_ trace: Trace) throws -> [Observed] {
        let ctx = VendCtx(price: trace.ctx["price"] ?? 0)
        let cells = VendImpl()
        var state = try stateOf(trace.from, trace.fromFields)
        var out: [Observed] = []

        for st in trace.steps {
            let step = vendStep(cells, ctx, state, try actionOf(st.action))
            // Always empty: `VendF` has no cases, so nothing can construct one.
            let effects: [String] = []
            let expect: Expect
            switch step {
            case .stay: expect = .stay
            case .ignored: expect = .ignored
            case let .go(next, _):
                state = next
                var want: [String: Int] = [:]
                if case let .go(_, fields) = st.expect { want = fields }
                expect = describe(next, want)
            }
            out.append(Observed(expect: expect, effects: effects))
        }
        return out
    }

    private func stateOf(_ name: String, _ f: [String: Int]) throws -> VendS {
        switch name {
        case "Idle": return .idle
        case "Charged": return .charged(credit: f["credit"] ?? 0)
        case "Dispensing": return .dispensing
        default: throw SpecError("dead-column: unknown state `\(name)`")
        }
    }

    private func actionOf(_ name: String) throws -> VendA {
        switch name {
        case "Insert": return .insert
        case "Select": return .select
        case "Refund": return .refund
        default: throw SpecError("dead-column: unknown action `\(name)`")
        }
    }

    private func describe(_ s: VendS, _ want: [String: Int]) -> Expect {
        switch s {
        case .idle: return .go(state: "Idle", fields: [:])
        case let .charged(credit):
            return .go(
                state: "Charged",
                fields: want["credit"] != nil ? ["credit": credit] : [:])
        case .dispensing: return .go(state: "Dispensing", fields: [:])
        }
    }
}

struct IgnoreHeavyAdapter: Adapter {
    let name = "ignore-heavy"
    let table = POLL_TABLE

    func replay(_ trace: Trace) throws -> [Observed] {
        let cells = PollImpl()
        var state = try stateOf(trace.from)
        var out: [Observed] = []

        for st in trace.steps {
            let step = pollStep(cells, PollCtx(), state, try actionOf(st.action))
            // Always empty: `PollF` has no cases. See EffectsNeverAdapter for
            // why this is a literal rather than a map.
            let effects: [String] = []
            let expect: Expect
            switch step {
            case .stay: expect = .stay
            case .ignored: expect = .ignored
            case let .go(next, _):
                state = next
                expect = .go(state: nameOf(next), fields: [:])
            }
            out.append(Observed(expect: expect, effects: effects))
        }
        return out
    }

    private func stateOf(_ name: String) throws -> PollS {
        switch name {
        case "Idle": return .idle
        case "Armed": return .armed
        case "Firing": return .firing
        case "Spent": return .spent
        default: throw SpecError("ignore-heavy: unknown state `\(name)`")
        }
    }

    private func actionOf(_ name: String) throws -> PollA {
        switch name {
        case "Arm": return .arm
        case "Tick": return .tick
        case "Fire": return .fire
        case "Reset": return .reset
        case "Abort": return .abort
        default: throw SpecError("ignore-heavy: unknown action `\(name)`")
        }
    }

    /// Exhaustive, so a state added to `PollS` without a name here is a build
    /// error rather than a rendering the fixture never matches.
    private func nameOf(_ s: PollS) -> String {
        switch s {
        case .idle: return "Idle"
        case .armed: return "Armed"
        case .firing: return "Firing"
        case .spent: return "Spent"
        }
    }
}

struct NoStaticExitAdapter: Adapter {
    let name = "no-static-exit"
    let table = BEACON_TABLE

    /// See `TimerAdapter.effectName`.
    static func effectName(_ f: BeaconF) -> String {
        switch f {
        case .flash: return "Flash"
        case .alarm: return "Alarm"
        }
    }

    func replay(_ trace: Trace) throws -> [Observed] {
        let cells = BeaconImpl()
        var state = try stateOf(trace.from)
        var out: [Observed] = []

        for st in trace.steps {
            let step = beaconStep(cells, BeaconCtx(), state, try actionOf(st.action))
            let effects = step.effects.map(Self.effectName)
            let expect: Expect
            switch step {
            case .stay: expect = .stay
            case .ignored: expect = .ignored
            case let .go(next, _):
                state = next
                expect = .go(state: nameOf(next), fields: [:])
            }
            out.append(Observed(expect: expect, effects: effects))
        }
        return out
    }

    private func stateOf(_ name: String) throws -> BeaconS {
        switch name {
        case "Idle": return .idle
        case "Blinking": return .blinking
        case "Fault": return .fault
        default: throw SpecError("no-static-exit: unknown state `\(name)`")
        }
    }

    private func actionOf(_ name: String) throws -> BeaconA {
        switch name {
        case "Start": return .start
        case "Pulse": return .pulse
        case "Clear": return .clear
        default: throw SpecError("no-static-exit: unknown action `\(name)`")
        }
    }

    private func nameOf(_ s: BeaconS) -> String {
        switch s {
        case .idle: return "Idle"
        case .blinking: return "Blinking"
        case .fault: return "Fault"
        }
    }
}

struct NoStaticEntryAdapter: Adapter {
    let name = "no-static-entry"
    let table = DOOR_TABLE

    /// See `TimerAdapter.effectName`.
    static func effectName(_ f: DoorF) -> String {
        switch f {
        case .thud: return "Thud"
        }
    }

    func replay(_ trace: Trace) throws -> [Observed] {
        let cells = DoorImpl()
        var state = try stateOf(trace.from)
        var out: [Observed] = []

        for st in trace.steps {
            let step = doorStep(cells, DoorCtx(), state, try actionOf(st.action))
            let effects = step.effects.map(Self.effectName)
            let expect: Expect
            switch step {
            case .stay: expect = .stay
            case .ignored: expect = .ignored
            case let .go(next, _):
                state = next
                expect = .go(state: nameOf(next), fields: [:])
            }
            out.append(Observed(expect: expect, effects: effects))
        }
        return out
    }

    private func stateOf(_ name: String) throws -> DoorS {
        switch name {
        case "Closed": return .closed
        case "Open": return .open
        case "Jammed": return .jammed
        default: throw SpecError("no-static-entry: unknown state `\(name)`")
        }
    }

    private func actionOf(_ name: String) throws -> DoorA {
        switch name {
        case "Push": return .push
        case "Pull": return .pull
        case "Kick": return .kick
        default: throw SpecError("no-static-entry: unknown action `\(name)`")
        }
    }

    private func nameOf(_ s: DoorS) -> String {
        switch s {
        case .closed: return "Closed"
        case .open: return "Open"
        case .jammed: return "Jammed"
        }
    }
}

struct UnreachableHeavyAdapter: Adapter {
    let name = "unreachable-heavy"
    let table = LINK_TABLE

    /// See `TimerAdapter.effectName`.
    static func effectName(_ f: LinkF) -> String {
        switch f {
        case .pong: return "Pong"
        }
    }

    func replay(_ trace: Trace) throws -> [Observed] {
        let ctx = LinkCtx(accept: (trace.ctx["accept"] ?? 0) != 0)
        let cells = LinkImpl()
        var state = try stateOf(trace.from)
        var out: [Observed] = []

        for st in trace.steps {
            let step = linkStep(cells, ctx, state, try actionOf(st.action))
            let effects = step.effects.map(Self.effectName)
            let expect: Expect
            switch step {
            case .stay: expect = .stay
            case .ignored: expect = .ignored
            case let .go(next, _):
                state = next
                expect = .go(state: nameOf(next), fields: [:])
            }
            out.append(Observed(expect: expect, effects: effects))
        }
        return out
    }

    private func stateOf(_ name: String) throws -> LinkS {
        switch name {
        case "Down": return .down
        case "Dialing": return .dialing
        case "Up": return .up
        default: throw SpecError("unreachable-heavy: unknown state `\(name)`")
        }
    }

    private func actionOf(_ name: String) throws -> LinkA {
        switch name {
        case "Dial": return .dial
        case "Ack": return .ack
        case "Hangup": return .hangup
        case "Ping": return .ping
        default: throw SpecError("unreachable-heavy: unknown action `\(name)`")
        }
    }

    private func nameOf(_ s: LinkS) -> String {
        switch s {
        case .down: return "Down"
        case .dialing: return "Dialing"
        case .up: return "Up"
        }
    }
}

/// Every adapter that has landed. A fixture with none is reported as skipped,
/// never as passed.
let adapters: [Adapter] = [
    TimerAdapter(), ToggleAdapter(), RetryAdapter(), JobAdapter(),
    EffectsNeverAdapter(), PayloadHoistAdapter(), DeadColumnAdapter(),
    IgnoreHeavyAdapter(), NoStaticExitAdapter(), NoStaticEntryAdapter(),
    UnreachableHeavyAdapter(),
]

// MARK: - Runner

/// The fixture directory: the first argument that is not a flag.
///
/// Skipping flags is defensive rather than decorative. `swift run` passes
/// everything after the executable name to the program, so a build flag in the
/// wrong position arrives here — and the first version took `--scratch-path`
/// as the fixture root and reported `cannot read --scratch-path/timer.tbl`.
/// That is a clear enough message, but only because the read was attempted;
/// ignoring flags makes the mistake harmless.
let root = CommandLine.arguments
    .dropFirst()
    .first { !$0.hasPrefix("--") } ?? "../spec/conformance"

/// Where to write renderings, if anywhere.
let emitDir: String? = CommandLine.arguments
    .first { $0.hasPrefix("--emit=") }
    .map { String($0.dropFirst("--emit=".count)) }
    .map { dir in
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        return dir
    }

func read(_ path: String) throws -> String {
    guard let s = try? String(contentsOfFile: path, encoding: .utf8) else {
        throw SpecError("cannot read \(path)")
    }
    return s
}

/// Write one rendering out, when asked with `--emit=<dir>`.
///
/// Nothing is compared here, and nothing is committed: `.tbl` and `.trace` are
/// the contract, and the renderings of it are produced by all three
/// implementations at check time and diffed against each other by
/// `tools/verify renderings-agree`.
func emit(_ dir: String?, _ name: String, _ ext: String, _ got: String) {
    guard let dir else { return }
    try? got.write(toFile: "\(dir)/\(name).\(ext)", atomically: true, encoding: .utf8)
}

var failed = 0
var steps = 0

for adapter in adapters {
    var errs: [String] = []
    let spec: Spec
    do {
        spec = try parseSpec(read("\(root)/\(adapter.name).tbl"), "\(adapter.name).tbl")
    } catch {
        print("FAIL \(adapter.name): \(error)")
        failed += 1
        continue
    }

    errs += checkTable(adapter.table, spec)
    emit(emitDir, adapter.name, "grid", Export.toGrid(adapter.table))
    // The lints carry the most per-language logic there is -- thresholds, the
    // dead-row/no-static-exit subsumption, the fully-static gate on
    // reachability -- and nothing compared them across languages until now.
    emit(emitDir, adapter.name, "mmd", Export.toMermaid(adapter.table))
    emit(emitDir, adapter.name, "lint", report(adapter.table, payloads: adapter.payloads))
    // The diagram. Three renderers agreeing on edge ORDER, not just on the
    // edge set -- which is the thing that had already drifted.
    emit(emitDir, adapter.name, "cov", Export.toCoverageReport(adapter.table))

    var traces: [Trace] = []
    do {
        traces = try parseTraces(
            read("\(root)/traces/\(adapter.name).trace"), "\(adapter.name).trace")
    } catch {
        errs.append("\(error)")
    }

    for t in traces {
        steps += t.steps.count
        do {
            let observed = try adapter.replay(t)
            for (i, pair) in zip(t.steps, observed).enumerated() {
                let (want, got) = pair
                let at = "\(t.name)[\(i)] \(want.action)"
                if want.expect != got.expect {
                    errs.append("\(at): got `\(got.expect)`, want `\(want.expect)`")
                }
                let gotEff = got.effects.map(lastSegment)
                let wantEff = want.effects.map(lastSegment)
                if gotEff != wantEff {
                    errs.append("\(at): effects got \(gotEff), want \(wantEff)")
                }
            }
        } catch {
            errs.append("\(t.name): \(error)")
        }
    }

    if errs.isEmpty {
        print(
            "ok   \(adapter.name)  (\(spec.states.count) states x \(spec.actions.count) "
                + "actions, \(traces.count) traces)")
        let warnings = report(adapter.table, payloads: adapter.payloads)
        for line in warnings.split(separator: "\n") where !line.isEmpty {
            print("       \(line)")
        }
    } else {
        print("FAIL \(adapter.name)")
        for e in errs { print("       \(e)") }
        failed += 1
    }
}

print("")
print("conformance (swift): \(adapters.count) tables, \(steps) trace steps, \(failed) failed")

// A fixture with no adapter is skipped, not passed -- and each one is NAMED, on
// its own line starting with `skip `, because that prefix is what `tools/verify`
// collects into the ledger it prints before the verdict. A count said how many
// were missing without saying which, and a count is invisible to the ledger, so
// the one place skips are supposed to be visible was the one place these never
// appeared.
if let entries = try? FileManager.default.contentsOfDirectory(atPath: root) {
    let declared = entries.filter { $0.hasSuffix(".tbl") }
        .map { String($0.dropLast(4)) }.sorted()
    let covered = Set(adapters.map { $0.name })
    for name in declared where !covered.contains(name) {
        print("skip \(name) (no Swift adapter)")
    }
}

if failed > 0 {
    // `exit`, not `fatalError`. stdout is block-buffered when piped, and
    // `fatalError` traps without flushing -- so the first run of this reported
    // "2 fixture(s) failed" with every diagnostic line swallowed. `exit`
    // flushes stdio on the way out.
    exit(1)
}
