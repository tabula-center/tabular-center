import Foundation
import TabulaCodegen

/// Tests for the validation layer, plus a determinism check of the emitted source.
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
// `tabular-center-kotlin/codegen/Tests.kt`, on the same machine.

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

// MARK: - Happy paths: walking the route backwards
//
// `back` names the action that walks a path in reverse, so for each hop
// `A -next-> B` the cell `(B, back)` derives to `GO(A)`. Over HANDLE cells
// only, like the forward direction, so an explicit cell wins and a path
// without `back` derives exactly what it did before.
//
// The machine ends at `Done`, which nothing but the back action leaves:
// `path-unterminated` asks whether anything leaves a path's end, and walking
// back is not leaving.

func backMachine(back: String, payBack: RawCell, doneBack: RawCell = RawCell("IGNORE")) -> RawMachine {
    RawMachine(
        machine: "Checkout", initial: "Cart",
        states: [RawVariant("Cart"), RawVariant("Addr"), RawVariant("Pay"), RawVariant("Done")],
        actions: [RawVariant("Next"), RawVariant("Back")],
        effects: [],
        rows: [
            RawRow("Cart", [RawCell("HANDLE"), RawCell("IGNORE")]),
            RawRow("Addr", [RawCell("HANDLE"), RawCell("HANDLE")]),
            RawRow("Pay", [RawCell("HANDLE"), payBack]),
            RawRow("Done", [RawCell("IGNORE"), doneBack]),
        ],
        paths: [
            RawPath(
                name: "checkout",
                elements: ["Cart", "Next", "Addr", "Next", "Pay", "Next", "Done"],
                back: back)
        ])
}

do {
    let derived = try buildDesc(backMachine(back: "Back", payBack: RawCell("HANDLE")))
    check("a hop's far side goes back one step", derived.rows[1][1] == .go(target: "Cart", args: "", effects: []))
    check("and the next one goes back to the one before", derived.rows[2][1] == .go(target: "Addr", args: "", effects: []))
    check("the forward direction still derives", derived.rows[0][0] == .go(target: "Addr", args: "", effects: []))

    let ending = try buildDesc(
        backMachine(back: "Back", payBack: RawCell("HANDLE"), doneBack: RawCell("HANDLE")))
    check("the path's end may be left by its own back action", ending.rows[3][1] == .go(target: "Pay", args: "", effects: []))

    let explicit = try buildDesc(backMachine(back: "Back", payBack: RawCell("GO", target: "Cart")))
    check("an explicit cell wins", explicit.rows[2][1] == .go(target: "Cart", args: "", effects: []))

    let plain = try buildDesc(backMachine(back: "", payBack: RawCell("HANDLE")))
    check("no back action, no reverse derivation", plain.rows[1][1] == .handle)
} catch {
    check("the back-deriving machines are accepted: \(error)", false)
}

expectError("a path that can still be left", "tabula::path-unterminated") {
    _ = try buildDesc(
        backMachine(back: "", payBack: RawCell("HANDLE"), doneBack: RawCell("HANDLE")))
}

expectError("a back action the machine does not declare", "tabula::path-unknown-state") {
    _ = try buildDesc(backMachine(back: "Backwards", payBack: RawCell("HANDLE")))
}

// MARK: - Golden emitted source

/// `timer.tbl`, as the macro would build it from syntax -- plus `Note`, an
/// effect no static cell names, so the payload-carrying handler is emitted and
/// compiled. `codegen-support/Types.swift` declares the types it names.
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
            // A payload type NESTED in the machine's enum, qualified the way
            // `MachineSyntax` now qualifies it. The file-scope protocol can
            // only resolve it qualified; this is what proves it does.
            RawVariant("Halt", hasPayload: true, fields: [(name: "reason", type: "Timer.Reason")]),
        ],
        rows: [
            RawRow("Idle", [RawCell("HANDLE"), RawCell("IGNORE"), RawCell("IGNORE")]),
            RawRow("Running", [
                RawCell("IGNORE"), RawCell("HANDLE"),
                // A static cell emitting a payload-carrying effect, arguments
                // and all. The dispatcher emits the call verbatim; `TABLE`
                // records the name.
                RawCell("GO", target: "Idle", effects: ["StopClock", "Halt(reason: .cancelled)"]),
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

/// The child in `Compose.swift`: a retry machine, written knowing nothing
/// about any parent.
func retryMachine(_ name: String, modifiers: [String] = []) -> RawMachine {
    RawMachine(
        machine: name,
        initial: "Ready",
        states: [
            RawVariant("Ready"),
            RawVariant("Waiting", hasPayload: true, fields: [(name: "attempt", type: "Int")]),
            RawVariant("Exhausted"),
        ],
        actions: [RawVariant("Attempt"), RawVariant("Elapsed"), RawVariant("Abort")],
        effects: [RawVariant("Sleep"), RawVariant("GiveUp")],
        rows: [
            RawRow("Ready", [RawCell("HANDLE"), RawCell("IGNORE"), RawCell("GO", target: "Exhausted")]),
            RawRow("Waiting", [RawCell("IGNORE"), RawCell("HANDLE"), RawCell("GO", target: "Exhausted")]),
            RawRow("Exhausted", [RawCell("IGNORE"), RawCell("IGNORE"), RawCell("IGNORE")]),
        ],
        prototypeModifiers: modifiers
    )
}

/// The parent in `Compose.swift`: its `Retrying` state holds the child's
/// state, and two of its cells delegate to the child.
func jobMachine(_ name: String, child: String, modifiers: [String] = []) -> RawMachine {
    RawMachine(
        machine: name,
        initial: "Idle",
        states: [
            RawVariant("Idle"),
            // The child's namespace is spelled by the alias: `.retry` is `Retry`.
            RawVariant("Retrying", hasPayload: true, fields: [
                (name: "child", type: String(child.prefix(1)).uppercased() + String(child.dropFirst()) + ".S"),
            ]),
            RawVariant("Done"),
        ],
        actions: [RawVariant("Run"), RawVariant("Tick"), RawVariant("Cancel")],
        effects: [RawVariant("Log")],
        rows: [
            RawRow("Idle", [RawCell("HANDLE"), RawCell("IGNORE"), RawCell("IGNORE")]),
            RawRow("Retrying", [
                RawCell("DELEGATE", child: child), RawCell("DELEGATE", child: child),
                RawCell("GO", target: "Done", effects: ["Log"]),
            ]),
            RawRow("Done", [RawCell("IGNORE"), RawCell("IGNORE"), RawCell("IGNORE")]),
        ],
        prototypeModifiers: modifiers,
        children: [ChildDesc(alias: child, stateType: "S", actionType: "A", effectType: "F", ctxType: "Ctx")]
    )
}

/// Every machine the check emits. `refused` ones must NOT compile, and are
/// written apart so `tools/verify` compiles them only with the fixture that
/// names them.
let emitted: [(name: String, raw: RawMachine, refused: Bool)] = [
    ("timer", timerRaw, false),
    ("timer-async", timerAsyncRaw, false),
    ("retry", retryMachine("Retry"), false),
    ("retry-async", retryMachine("RetryAsync", modifiers: ["async", "throws"]), false),
    ("job", jobMachine("Job", child: "retry"), false),
    // Colorless child in a colored parent: allowed, and compiled.
    ("job-async", jobMachine("JobAsync", child: "retry", modifiers: ["async", "throws"]), false),
    // Colored child in a colorless parent: color flows one way, so refused.
    ("job-mixed", jobMachine("JobMixed", child: "retryAsync"), true),
]

/// Where to write the emitted source for `tools/verify` to compile, if asked.
/// Never into the tree: generated code is not committed, as source or as a
/// golden. The compile stages prove the output is Swift; this file proves
/// what a golden diff also implied, that emission is deterministic.
let emitDir = CommandLine.arguments
    .first { $0.hasPrefix("--emit=") }
    .map { String($0.dropFirst("--emit=".count)) }

if let dir = emitDir {
    try? FileManager.default.createDirectory(atPath: "\(dir)/refused", withIntermediateDirectories: true)
}

for (name, machine, refused) in emitted {
    do {
        let desc = try buildDesc(machine)
        let source = emit(desc)
        check("\(name) emits deterministically", source == emit(desc))
        if let dir = emitDir {
            // `.emitted.swift`, not `.swift`: swiftc refuses two inputs with the
            // same base name even from different directories, and the complete
            // implementation it is compiled with is `complete/<name>.swift`.
            let sub = refused ? "\(dir)/refused" : dir
            try source.write(toFile: "\(sub)/\(name).emitted.swift", atomically: true, encoding: .utf8)
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
