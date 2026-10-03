// Tests for the validation layer, plus a determinism check of the emitted source.
//
// Every diagnostic in `spec/diagnostics.md` that concerns the *declaration*
// has a case here — which is the point of `buildDesc` existing at all. They
// would otherwise live in the macro, which cannot be tested without
// swift-syntax, which cannot be fetched in a sandbox with no network.
import Foundation
import TabularCenterCodegen

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
    } catch let e as TabularCenterError {
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

check("a well-formed machine builds", (try? buildDesc(raw()))?.rows.count == 2)

expectError("row with too few cells", "tabular-center::row-arity") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("HANDLE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))
}

expectError("a state with no row", "tabular-center::missing-row") {
    _ = try buildDesc(raw(rows: [RawRow("Idle", [RawCell("HANDLE"), RawCell("IGNORE")])]))
}

expectError("rows out of declaration order", "tabular-center::missing-row") {
    _ = try buildDesc(raw(rows: [
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
        RawRow("Idle", [RawCell("HANDLE"), RawCell("IGNORE")]),
    ]))
}

expectError("a row for an undeclared state", "tabular-center::extra-row") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("HANDLE"), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
        RawRow("Nope", [RawCell("IGNORE"), RawCell("IGNORE")]),
    ]))
}

expectError("GO to an undeclared state", "tabular-center::unknown-state") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("GO", target: "Nope"), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))
}

expectError("GO to a payload state with no literal args", "tabular-center::go-target") {
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

expectError("emitting an undeclared effect", "tabular-center::unknown-effect") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("GO", target: "Idle", effects: ["Nope"]), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))
}

expectError("EMIT with no effects", "tabular-center::empty-emit") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("EMIT"), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))
}

expectError("DELEGATE to an undeclared child", "tabular-center::unknown-child") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("DELEGATE", child: "retry"), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))
}

expectError("an unrecognised cell kind", "tabular-center::unknown-cell") {
    _ = try buildDesc(raw(rows: [
        RawRow("Idle", [RawCell("MAYBE"), RawCell("IGNORE")]),
        RawRow("Running", [RawCell("IGNORE"), RawCell("HANDLE")]),
    ]))
}

expectError("an undeclared initial state", "tabular-center::unknown-state") {
    _ = try buildDesc(raw(initial: "Nope"))
}

let spineQuiet = [RawCell("IGNORE"), RawCell("IGNORE"), RawCell("IGNORE")]

func spineConn(_ rows: [RawRow], paths: [RawPath]) -> RawMachine {
    RawMachine(
        machine: "Conn", initial: "Idle",
        states: [RawVariant("Idle"), RawVariant("Connecting"), RawVariant("Live"), RawVariant("Failed")],
        actions: [RawVariant("Start"), RawVariant("Ready"), RawVariant("Drop")],
        effects: [RawVariant("Go")], rows: rows, paths: paths)
}

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
    check("... and, hops aside, emits byte-identical source, TABLE included",
          emit(derived.withoutHops) == emit(longhand))
    check("the path's two hops are recorded",
          derived.hops == [HopDesc(from: 0, action: 0, to: 1), HopDesc(from: 1, action: 1, to: 2)])

    let lines = emit(derived).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    check("(Connecting, Ready) can end anywhere: a HANDLE is in its row",
          hopOutcomes(derived, derived.hops[1]) == [0, 1, 2, 3])
    check("(Idle, Start) ends in Connecting or stays Idle", hopOutcomes(derived, derived.hops[0]) == [0, 1])
    check("the member takes the action that arrived",
          lines.contains("    static func connectingReady(_ cells: ConnCells, _ ctx: Conn.Ctx, _ action: Conn.A) -> ConnectingReady {"))
    check("every state but Live is a required label, and rethrows",
          lines.contains("        func elvis(idle: ([Conn.F]) throws -> [Conn.F], connecting: ([Conn.F]) throws -> [Conn.F], failed: ([Conn.F]) throws -> [Conn.F]) rethrows -> [Conn.F] {"))
    check("a state the row cannot produce is a trap, not a default",
          lines.contains("        case .live: fatalError(\"tabular-center: the `Idle` row cannot produce `Live`\")")
            && !lines.contains { $0.hasSuffix("default:") })
    check("without the path, the same rows are a different machine", underived.rows != longhand.rows)
    check("a HANDLE no hop names is left alone", derived.rows[1][2] == .handle)
} catch {
    checks += 1
    failures += 1
    print("FAIL additive test: \(error)")
}

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

expectError("a path that can still be left", "tabular-center::path-unterminated") {
    _ = try buildDesc(
        backMachine(back: "", payBack: RawCell("HANDLE"), doneBack: RawCell("HANDLE")))
}

expectError("a back action the machine does not declare", "tabular-center::path-unknown-state") {
    _ = try buildDesc(backMachine(back: "Backwards", payBack: RawCell("HANDLE")))
}

func timerMachine(_ name: String, modifiers: [String] = [], render: RenderDesc? = nil) -> RawMachine {
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
            RawVariant("Halt", hasPayload: true, fields: [(name: "reason", type: "Timer.Reason")]),
        ],
        rows: [
            RawRow("Idle", [RawCell("HANDLE"), RawCell("IGNORE"), RawCell("IGNORE")]),
            RawRow("Running", [
                RawCell("IGNORE"), RawCell("HANDLE"),
                RawCell("GO", target: "Idle", effects: ["StopClock", "Halt(reason: .cancelled)"]),
            ]),
            RawRow("Done", [
                RawCell("GO", target: "Running", args: "(since: 0)", effects: ["StartClock"]),
                RawCell("IGNORE"), RawCell("IGNORE"),
            ]),
        ],
        prototypeModifiers: modifiers,
        render: render
    )
}

let timerRaw = timerMachine("Timer")

let timerAsyncRaw = timerMachine("TimerAsync", modifiers: ["async", "throws"])

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

func jobMachine(_ name: String, child: String, modifiers: [String] = []) -> RawMachine {
    RawMachine(
        machine: name,
        initial: "Idle",
        states: [
            RawVariant("Idle"),
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

do {
    let plain = try buildDesc(timerMachine("RenderProbe"))
    let color = RenderDesc(modifiers: ["@MainActor"])
    let rendered = try buildDesc(timerMachine("RenderProbe", render: color))
    let out = emit(rendered)
    let outLines = out.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let plainLines = emit(plain).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    check("the render prototype survives buildDesc", rendered.render == color)
    check(
        "without a render prototype nothing rendering-related is emitted",
        !plainLines.contains { $0.hasSuffix("Renders {") || $0.hasSuffix("Render one state. No `default:` branch.") }
    )

    var rest = outLines
    if let a = rest.firstIndex(of: "/// The rendering surface: one required member per state, the state narrowed."),
       let b = rest[a...].firstIndex(of: "}") {
        rest.removeSubrange(a...(b + 1))
    }
    if let a = rest.firstIndex(of: "    /// Render one state. No `default:` branch."),
       let b = rest[a...].firstIndex(of: "    }") {
        rest.removeSubrange((a - 1)...b)
    }
    check("... and the rest of the output is untouched by one", rest == plainLines)

    check("a renderer for Idle, in the prototype's color", outLines.contains("    @MainActor func renderIdle() -> Void"))
    check(
        "a renderer for Running, narrowed",
        outLines.contains("    @MainActor func renderRunning(_ state: RenderProbe.Running) -> Void")
    )
    check("a renderer for Done", outLines.contains("    @MainActor func renderDone() -> Void"))
    check(
        "the dispatcher carries the color too",
        outLines.contains("    @MainActor static func render(_ renders: RenderProbeRenders, _ s: RenderProbe.S) -> Void {")
    )
    check("a bound arm for Running", outLines.contains("        case let .running(since):"))
    check(
        "... building the narrowed struct",
        outLines.contains("            return renders.renderRunning(RenderProbe.Running(since: since))")
    )
    if let a = outLines.firstIndex(of: "    /// Render one state. No `default:` branch."),
       let b = outLines[a...].firstIndex(of: "    }") {
        check("the dispatcher has no default branch", !outLines[a...b].contains { $0.hasSuffix("default:") })
    } else {
        check("the dispatcher was found", false)
    }
} catch {
    checks += 1
    failures += 1
    print("FAIL render test: \(error)")
}

do {
    let view = RenderDesc(modifiers: ["@MainActor"], builder: "ViewBuilder", conformance: "View")
    let out = emit(try buildDesc(timerMachine("ViewProbe", render: view)))
    let lines = out.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    check("an associated type per state", lines.contains("    associatedtype RunningBody: View"))
    check(
        "... and a builder requirement returning it, narrowed",
        lines.contains("    @MainActor @ViewBuilder func renderRunning(_ state: ViewProbe.Running) -> RunningBody")
    )
    check("a payload-free state takes nothing", lines.contains("    @MainActor @ViewBuilder func renderIdle() -> IdleBody"))
    check(
        "render is available where opaque types are",
        lines.contains("    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)")
    )
    check(
        "render is generic and opaque",
        lines.contains(
            "    @MainActor @ViewBuilder static func render<R: ViewProbeRenders>(_ renders: R, _ s: ViewProbe.S) -> some View {"
        )
    )
    if let a = lines.firstIndex(of: "    /// Render one state. No `default:` branch."),
       let b = lines[a...].firstIndex(of: "    }") {
        let body = lines[a...b]
        check("no `return` in a builder body, which would switch the builder off", !body.contains { $0.hasPrefix("            return") })
        check("... and still no default branch", !body.contains { $0.hasSuffix("default:") })
        check("a bare arm per state", body.contains("            renders.renderRunning(ViewProbe.Running(since: since))"))
    } else {
        check("the builder dispatcher was found", false)
    }

    let colored = RenderDesc(modifiers: ["async"], builder: "ViewBuilder", conformance: "View")
    check(
        "a colored builder renderer is refused, by name",
        emit(try buildDesc(timerMachine("ViewProbe", render: colored)))
            .split(separator: "\n").contains { $0.hasPrefix("#error(") && $0.hasSuffix("step asynchronously\")") }
    )
    let unconstrained = RenderDesc(builder: "ViewBuilder")
    check(
        "a builder renderer with no conformance is refused, by name",
        emit(try buildDesc(timerMachine("ViewProbe", render: unconstrained)))
            .split(separator: "\n").contains { $0.hasPrefix("#error(") && $0.hasSuffix("such as `View`\")") }
    )
} catch {
    checks += 1
    failures += 1
    print("FAIL builder render test: \(error)")
}

let emitted: [(name: String, raw: RawMachine, refused: Bool)] = [
    ("timer", timerRaw, false),
    ("timer-async", timerAsyncRaw, false),
    ("timer-render", timerMachine("TimerRender", modifiers: ["async", "throws"], render: RenderDesc(returnType: "String")), false),
    ("timer-view", timerMachine("TimerView", render: RenderDesc(builder: "ViewishBuilder", conformance: "Viewish")), false),
    ("connect", RawMachine(
        machine: "Connect", initial: "Idle",
        states: [RawVariant("Idle"), RawVariant("Connecting"), RawVariant("Live"), RawVariant("Failed")],
        actions: [RawVariant("Start"), RawVariant("Ready"), RawVariant("Drop")],
        effects: [RawVariant("Banner")],
        rows: [
            RawRow("Idle", [RawCell("HANDLE"), RawCell("IGNORE"), RawCell("IGNORE")]),
            RawRow("Connecting", [RawCell("IGNORE"), RawCell("HANDLE"), RawCell("HANDLE")]),
            RawRow("Live", [RawCell("IGNORE"), RawCell("IGNORE"), RawCell("IGNORE")]),
            RawRow("Failed", [RawCell("IGNORE"), RawCell("IGNORE"), RawCell("IGNORE")]),
        ],
        paths: [RawPath(name: "connect", elements: ["Idle", "Start", "Connecting", "Ready", "Live"])]
    ), false),
    ("retry", retryMachine("Retry"), false),
    ("retry-async", retryMachine("RetryAsync", modifiers: ["async", "throws"]), false),
    ("job", jobMachine("Job", child: "retry"), false),
    ("job-async", jobMachine("JobAsync", child: "retry", modifiers: ["async", "throws"]), false),
    ("job-mixed", jobMachine("JobMixed", child: "retryAsync"), true),
]

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
