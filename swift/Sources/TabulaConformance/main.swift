import Foundation
import Tabula
import TabulaTesting

/// Runs the shared `spec/conformance` fixtures against the Swift
/// implementation.
///
/// Three things are compared, and the third only exists because there are three
/// implementations:
///
/// 1. The generated table, cell by cell.
/// 2. Traces: outcomes and effects, step by step.
/// 3. The golden `.grid` file, **byte for byte**. Rust writes these with
///    `--bless`; Kotlin and Swift read and never bless, so a renderer that
///    drifts by a single space fails rather than quietly rewriting the shared
///    snapshot.
///
/// Foundation is imported here and nowhere in `TabulaTesting`: the runner needs
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
    func replay(_ trace: Trace) throws -> [Observed]
}

struct TimerAdapter: Adapter {
    let name = "timer"
    let table = TIMER_TABLE

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

/// Every adapter that has landed. A fixture with none is reported as skipped,
/// never as passed.
let adapters: [Adapter] = [
    TimerAdapter(), ToggleAdapter(), RetryAdapter(), JobAdapter(),
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

func read(_ path: String) throws -> String {
    guard let s = try? String(contentsOfFile: path, encoding: .utf8) else {
        throw SpecError("cannot read \(path)")
    }
    return s
}

/// Compare a generated artifact against its committed golden file.
///
/// Never blesses: Rust owns `--bless`, so a Swift renderer or lint that drifts
/// fails here rather than quietly rewriting the shared snapshot.
func checkGolden(_ name: String, _ ext: String, _ got: String) -> [String] {
    let path = "\(root)/\(name).\(ext)"
    guard let want = try? String(contentsOfFile: path, encoding: .utf8) else {
        return ["no golden \(ext) at \(path)"]
    }
    if got == want { return [] }

    var errs = ["\(ext) differs from \(path):"]
    let g = got.split(separator: "\n", omittingEmptySubsequences: false)
    let w = want.split(separator: "\n", omittingEmptySubsequences: false)
    for n in 0..<min(g.count, w.count) where g[n] != w[n] {
        errs.append("  line \(n): swift  |\(g[n])|")
        errs.append("  line \(n): golden |\(w[n])|")
    }
    return errs
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
    errs += checkGolden(adapter.name, "grid", Export.toGrid(adapter.table))
    // The lints carry the most per-language logic there is -- thresholds, the
    // dead-row/no-static-exit subsumption, the fully-static gate on
    // reachability -- and nothing compared them across languages until now.
    errs += checkGolden(adapter.name, "lint", report(adapter.table))
    // The diagram. Three renderers agreeing on edge ORDER, not just on the
    // edge set -- which is the thing that had already drifted.
    errs += checkGolden(adapter.name, "puml", Export.toPlantuml(adapter.table))
    errs += checkGolden(adapter.name, "cov", Export.toCoverageReport(adapter.table))

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
        let warnings = report(adapter.table)
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

// A fixture with no adapter is skipped, not passed.
if let entries = try? FileManager.default.contentsOfDirectory(atPath: root) {
    let declared = entries.filter { $0.hasSuffix(".tbl") }.count
    if declared > adapters.count {
        print("       \(declared - adapters.count) fixture(s) have no Swift adapter (skipped)")
    }
}

if failed > 0 {
    // `exit`, not `fatalError`. stdout is block-buffered when piped, and
    // `fatalError` traps without flushing -- so the first run of this reported
    // "2 fixture(s) failed" with every diagnostic line swallowed. `exit`
    // flushes stdio on the way out.
    exit(1)
}
