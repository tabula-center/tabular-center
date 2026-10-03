// Runs the shared `spec/conformance` fixtures against the Swift
// implementation.
//
// Three things are compared, and the third only exists because there are three
// implementations:
//
// 1. The generated table, cell by cell.
// 2. Traces: outcomes and effects, step by step.
// 3. Nothing else here: the renderings (`.grid`, `.mmd`, `.lint`, `.cov`) are
//    written out with `--emit=<dir>` and diffed against the other two
//    implementations' by `tools/verify renderings-agree`, rather than each
//    being compared against a committed copy of one implementation's output.
//
// Foundation is imported here and nowhere in `TabularCenterTesting`: the runner needs
// file IO, and a published library should not put Foundation on every
// consumer's link line to trim a string.
import Foundation
import TabularCenter
import TabularCenterTesting

/// Outcome of one replayed step, in fixture vocabulary.
struct Observed {
    let expect: Expect
    let effects: [String]
}

/// Binds one fixture to one real machine.
protocol Adapter {
    var name: String { get }
    var table: Table { get }

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

let adapters: [Adapter] = [
    TimerAdapter(), ToggleAdapter(), RetryAdapter(), JobAdapter(),
    EffectsNeverAdapter(), PayloadHoistAdapter(), DeadColumnAdapter(),
    IgnoreHeavyAdapter(), NoStaticExitAdapter(), NoStaticEntryAdapter(),
    UnreachableHeavyAdapter(),
]

let root = CommandLine.arguments
    .dropFirst()
    .first { !$0.hasPrefix("--") } ?? "../spec/conformance"

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
    emit(emitDir, adapter.name, "mmd", Export.toMermaid(adapter.table))
    emit(emitDir, adapter.name, "lint", report(adapter.table, payloads: adapter.payloads))
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

do {
    let algebra = replayStepAlgebra(try read("\(root)/step-algebra.cases"))
    if algebra.failures.isEmpty {
        print("ok   step-algebra (\(algebra.cases) cases)")
    } else {
        print("FAIL step-algebra")
        for f in algebra.failures { print("       \(f)") }
        failed += 1
    }
} catch {
    print("FAIL step-algebra: \(error)")
    failed += 1
}

print("")
print("conformance (swift): \(adapters.count) tables, \(steps) trace steps, \(failed) failed")

if let entries = try? FileManager.default.contentsOfDirectory(atPath: root) {
    let declared = entries.filter { $0.hasSuffix(".tbl") }
        .map { String($0.dropLast(4)) }.sorted()
    let covered = Set(adapters.map { $0.name })
    for name in declared where !covered.contains(name) {
        print("skip \(name) (no Swift adapter)")
    }
}

if failed > 0 {
    exit(1)
}
