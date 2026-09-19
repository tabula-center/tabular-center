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

// MARK: - Happy paths: the additive test
//
// `spec/happy-paths.md`, checked rather than stated. A machine whose `HANDLE`
// cells a spine turns into `GO`s, and the same machine with those `GO`s written
// by hand, must be indistinguishable downstream. Equal emitted source is the
// strong form: `TABLE` is a literal inside it, and every golden is a pure
// function of `TABLE`. Kotlin's twin is `runAdditiveTest` in
// `kotlin/codegen/Tests.kt`, on the same machine.

let spineQuiet = [RawCell("IGNORE"), RawCell("IGNORE"), RawCell("IGNORE")]

func spineConn(_ rows: [RawRow], paths: [RawPath]) -> RawMachine {
    RawMachine(
        machine: "Conn", initial: "Idle",
        states: [RawVariant("Idle"), RawVariant("Connecting"), RawVariant("Live"), RawVariant("Failed")],
        actions: [RawVariant("Start"), RawVariant("Ready"), RawVariant("Drop")],
        effects: [RawVariant("Go")], rows: rows, paths: paths)
}

// Idle -Start-> Connecting -Ready-> Live, and Live is terminal. Drop from
// Connecting is a HANDLE the spine does not name, so it must survive.
let spineConnect = RawPath(name: "connect", elements: ["Idle", "Start", "Connecting", "Ready", "Live"])
let spineRows = [
    RawRow("Idle", [RawCell("HANDLE"), RawCell("IGNORE"), RawCell("IGNORE")]),
    RawRow("Connecting", [RawCell("IGNORE"), RawCell("HANDLE"), RawCell("HANDLE")]),
    RawRow("Live", spineQuiet),
    RawRow("Failed", spineQuiet),
]
let spineLonghandRows = [
    RawRow("Idle", [RawCell("GO", target: "Connecting"), RawCell("IGNORE"), RawCell("IGNORE")]),
    RawRow("Connecting", [RawCell("IGNORE"), RawCell("GO", target: "Live"), RawCell("HANDLE")]),
    RawRow("Live", spineQuiet),
    RawRow("Failed", spineQuiet),
]

do {
    let derived = try buildDesc(spineConn(spineRows, paths: [spineConnect]))
    let longhand = try buildDesc(spineConn(spineLonghandRows, paths: []))
    let underived = try buildDesc(spineConn(spineRows, paths: []))

    check("a spine-derived machine equals its longhand twin", derived.rows == longhand.rows)
    check("... and emits byte-identical source, TABLE included", emit(derived) == emit(longhand))
    // The control: without it, a `derive` that did nothing would still pass the
    // two checks above whenever the longhand twin was written wrong.
    check("without the path, the same rows are a different machine", underived.rows != longhand.rows)
    check("a HANDLE no hop names is left alone", derived.rows[1][2] == .handle)
} catch {
    checks += 1
    failures += 1
    print("FAIL additive test: \(error)")
}

// MARK: - Golden emitted source

/// `timer.tbl`, as the macro would build it from syntax -- plus `Note`, an
/// effect no static cell names, so the payload-carrying handler is emitted and
/// compiled. `codegen-support/TimerTypes.swift` declares the types it names.
func timerMachine(_ name: String, modifiers: [String] = []) -> RawMachine {
    RawMachine(
        machine: name,
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
        effects: [
            RawVariant("StartClock"),
            RawVariant("StopClock"),
            RawVariant("Note", hasPayload: true, fields: [(name: "text", type: "String")]),
        ],
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
        ],
        prototypeModifiers: modifiers
    )
}

let timerRaw = timerMachine("Timer")

/// The same machine, colored. `async throws` must land after the parameter
/// list and put `try await` on every call into a cell -- the emitter used to
/// splat both before `func`, which is not Swift.
let timerAsyncRaw = timerMachine("TimerAsync", modifiers: ["async", "throws"])

let goldenDir = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") } ?? "codegen-golden"
let bless = CommandLine.arguments.contains("--bless")
/// Where to write the emitted source for `tools/verify` to compile, if asked.
let emitDir = CommandLine.arguments
    .first { $0.hasPrefix("--emit=") }
    .map { String($0.dropFirst("--emit=".count)) }

if let dir = emitDir {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
}

for (name, machine) in [("timer", timerRaw), ("timer-async", timerAsyncRaw)] {
    do {
        let source = emit(try buildDesc(machine))
        if let dir = emitDir {
            // `.emitted.swift`, not `.swift`: swiftc refuses two inputs with the
            // same base name even from different directories, and the complete
            // implementation it is compiled with is `complete/<name>.swift`.
            try source.write(toFile: "\(dir)/\(name).emitted.swift", atomically: true, encoding: .utf8)
        }
        let path = "\(goldenDir)/\(name).swift.golden"
        if bless {
            try source.write(toFile: path, atomically: true, encoding: .utf8)
            print("blessed \(name)")
        } else if let want = try? String(contentsOfFile: path, encoding: .utf8) {
            checks += 1
            if source == want {
                print("ok   \(name)")
            } else {
                failures += 1
                print("FAIL \(name): emitted source differs from \(path)")
                let g = source.split(separator: "\n", omittingEmptySubsequences: false)
                let w = want.split(separator: "\n", omittingEmptySubsequences: false)
                for n in 0..<min(g.count, w.count) where g[n] != w[n] {
                    print("       line \(n): got    |\(g[n])|")
                    print("       line \(n): golden |\(w[n])|")
                }
            }
        } else {
            // A missing golden is a SKIP, not a failure. The first one can only
            // be written by running this, and shipping a check that must fail
            // once before it can pass teaches people to ignore it.
            //
            // Visible rather than silent, the same way a conformance fixture
            // with no adapter is reported.
            print("skip \(name): no golden yet at \(path)")
            print("     TABULA_BLESS=1 ./tools/verify swift-codegen   (then commit it)")
        }
    } catch {
        checks += 1
        failures += 1
        print("FAIL \(name): \(error)")
    }
}

if failures == 0 {
    print("ok   swift codegen (\(checks) checks)")
} else {
    print("FAIL swift codegen (\(failures) of \(checks) checks failed)")
    exit(1)
}
