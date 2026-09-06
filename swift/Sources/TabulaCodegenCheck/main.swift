import Foundation
import TabulaCodegen

/// Tests for the validation layer, plus a golden diff of the emitted source.
///
/// Every diagnostic in `spec/diagnostics.md` that concerns the *declaration*
/// has a case here — which is the point of `buildDesc` existing at all. They
/// would otherwise live in the macro, which cannot be tested without
/// swift-syntax, which cannot be fetched in a sandbox with no network.

var failures = 0
var checks = 0

func check(_ what: String, _ condition: Bool) {
    checks += 1
    if !condition {
        failures += 1
        print("FAIL \(what)")
    }
}

func expectError(_ what: String, _ code: String, _ body: () throws -> Void) {
    checks += 1
    do {
        try body()
        failures += 1
        print("FAIL \(what): expected \(code), got no error")
    } catch let e as TabulaError {
        if e.code != code {
            failures += 1
            print("FAIL \(what): expected \(code), got \(e.code)")
            print("       \(e.message)")
        }
    } catch {
        failures += 1
        print("FAIL \(what): unexpected \(error)")
    }
}

func raw(
    states: [RawVariant] = [RawVariant("Idle"), RawVariant("Running", hasPayload: true)],
    actions: [RawVariant] = [RawVariant("Start"), RawVariant("Tick")],
    effects: [RawVariant] = [RawVariant("Go")],
    rows: [RawRow] = [
        RawRow("Idle", [RawCell("HANDLE"), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ],
    initial: String = "Idle",
    children: [ChildDesc] = []
) -> RawMachine {
    RawMachine(
        machine: "T", initial: initial, states: states, actions: actions,
        effects: effects, rows: rows, children: children)
}

// MARK: - Validation

check("a well-formed machine builds", (try? buildDesc(raw()))?.rows.count == 2)

expectError("row with too few cells", "tabula::row-arity") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("HANDLE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))
}

expectError("a state with no row", "tabula::missing-row") {
    _ = try buildDesc(raw(rows: [RawRow("Idle", [RawCell("HANDLE"), RawCell("IGNORE")])]))
}

expectError("rows out of declaration order", "tabula::missing-row") {
    _ = try buildDesc(raw(rows: [
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
        RawRow("Idle", [RawCell("HANDLE"), RawCell("IGNORE")]),
    ]))
}

expectError("a row for an undeclared state", "tabula::extra-row") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("HANDLE"), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
        RawRow("Nope", [RawCell("IGNORE"), RawCell("IGNORE")]),
    ]))
}

expectError("GO to an undeclared state", "tabula::unknown-state") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("GO", target: "Nope"), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))
}

// Rule R3: a GO cell is resolved entirely by the generator, so its target must
// be constructible without developer code.
expectError("GO to a payload state with no literal args", "tabula::go-target") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("GO", target: "Running"), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))
}

check(
    "GO to a payload state WITH literal args is fine",
    (try? buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("GO", target: "Running", args: "(since: 0)"), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))) != nil)

expectError("emitting an undeclared effect", "tabula::unknown-effect") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("GO", target: "Idle", effects: ["Nope"]), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))
}

expectError("EMIT with no effects", "tabula::empty-emit") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("EMIT"), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))
}

expectError("DELEGATE to an undeclared child", "tabula::unknown-child") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("DELEGATE", child: "retry"), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))
}

expectError("an unrecognised cell kind", "tabula::unknown-cell") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("MAYBE"), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))
}

expectError("an undeclared initial state", "tabula::unknown-state") {
    _ = try buildDesc(raw(initial: "Nope"))
}

// MARK: - Golden emitted source

/// `timer.tbl`, as the macro would build it from syntax.
let timerRaw = RawMachine(
    machine: "Timer",
    initial: "Idle",
    states: [
        RawVariant("Idle"),
        RawVariant("Running", hasPayload: true, fields: [(name: "since", type: "Int")]),
        RawVariant("Done"),
    ],
    actions: [
        RawVariant("Start"),
        RawVariant("Tick", hasPayload: true, fields: [(name: "now", type: "Int")]),
        RawVariant("Cancel"),
    ],
    effects: [RawVariant("StartClock"), RawVariant("StopClock")],
    rows: [
        RawRow("Idle", [RawCell("HANDLE"), RawCell("IGNORE"), RawCell("IGNORE")]),
        RawRow("Running", [
            RawCell("IGNORE"), RawCell("HANDLE"),
            RawCell("GO", target: "Idle", effects: ["StopClock"]),
        ]),
        RawRow("Done", [
            RawCell("GO", target: "Running", args: "(since: 0)", effects: ["StartClock"]),
            RawCell("IGNORE"), RawCell("IGNORE"),
        ]),
    ]
)

let goldenDir = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") } ?? "codegen-golden"
let bless = CommandLine.arguments.contains("--bless")

do {
    let source = emit(try buildDesc(timerRaw))
    let path = "\(goldenDir)/timer.swift.golden"
    if bless {
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        print("blessed timer")
    } else if let want = try? String(contentsOfFile: path, encoding: .utf8) {
        checks += 1
        if source == want {
            print("ok   timer")
        } else {
            failures += 1
            print("FAIL timer: emitted source differs from \(path)")
            let g = source.split(separator: "\n", omittingEmptySubsequences: false)
            let w = want.split(separator: "\n", omittingEmptySubsequences: false)
            for n in 0..<min(g.count, w.count) where g[n] != w[n] {
                print("       line \(n): got    |\(g[n])|")
                print("       line \(n): golden |\(w[n])|")
            }
        }
    } else {
        // A missing golden is a SKIP, not a failure. The first one can only be
        // written by running this, and shipping a check that must fail once
        // before it can pass is a good way to teach people to ignore it.
        //
        // Visible rather than silent, the same way a conformance fixture with
        // no adapter is reported.
        print("skip timer: no golden yet at \(path)")
        print("     ./tools/verify swift-codegen -- --bless   (then commit it)")
    }
} catch {
    checks += 1
    failures += 1
    print("FAIL timer: \(error)")
}

if failures == 0 {
    print("ok   swift codegen (\(checks) checks)")
} else {
    print("FAIL swift codegen (\(failures) of \(checks) checks failed)")
    exit(1)
}
