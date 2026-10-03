/// The flat, stringly-typed shape a macro can fill in without judgement.
///
/// The macro is the one piece that needs swift-syntax, so it is the one piece
/// that stays hard to test. The remedy is to make it as small and as dumb as
/// possible: reading syntax nodes into strings is mechanical, while
/// *validating* those strings is where the decisions and the diagnostics live.
///
/// So the macro produces a `RawMachine` and calls `buildDesc`. Everything below
/// runs and is tested with no swift-syntax anywhere.
/// A happy path: a named route through the matrix, from a state to a state.
///
/// Named because a machine may have more than one, and the narrowed calling
/// surface has to say which it narrows to.
public struct RawPath {
    public let name: String

    public let elements: [String]

    public let back: String

    public init(name: String, elements: [String], back: String = "") {
        self.name = name
        self.elements = elements
        self.back = back
    }

    public var states: [String] {
        elements.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
    }

    public var actions: [String] {
        elements.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
    }

    public var hops: [(from: String, action: String, to: String)] {
        guard elements.count >= 3, elements.count % 2 == 1 else { return [] }
        return (0..<(elements.count / 2)).map {
            (elements[$0 * 2], elements[$0 * 2 + 1], elements[$0 * 2 + 2])
        }
    }

    public var reverseHops: [(from: String, action: String, to: String)] {
        guard !back.isEmpty else { return [] }
        return hops.map { (from: $0.to, action: back, to: $0.from) }
    }
}

public struct RawMachine {
    public let machine: String
    public let stateType: String
    public let actionType: String
    public let effectType: String
    public let ctxType: String
    public let initial: String
    public let states: [RawVariant]
    public let actions: [RawVariant]
    public let effects: [RawVariant]
    public let rows: [RawRow]
    public let prototypeModifiers: [String]
    public let children: [ChildDesc]

    public let paths: [RawPath]
    public let render: RenderDesc?

    public init(
        machine: String,
        stateType: String = "S",
        actionType: String = "A",
        effectType: String = "F",
        ctxType: String = "Ctx",
        initial: String,
        states: [RawVariant],
        actions: [RawVariant],
        effects: [RawVariant] = [],
        rows: [RawRow],
        prototypeModifiers: [String] = [],
        children: [ChildDesc] = [],
        paths: [RawPath] = [],
        render: RenderDesc? = nil
    ) {
        self.machine = machine
        self.stateType = stateType
        self.actionType = actionType
        self.effectType = effectType
        self.ctxType = ctxType
        self.initial = initial
        self.states = states
        self.actions = actions
        self.effects = effects
        self.rows = rows
        self.prototypeModifiers = prototypeModifiers
        self.children = children
        self.paths = paths
        self.render = render
    }
}

/// A variant as the macro reads it, before validation.
public struct RawVariant {
    public let name: String
    public let hasPayload: Bool
    public let fields: [(name: String, type: String)]

    public init(_ name: String, hasPayload: Bool = false, fields: [(name: String, type: String)] = []) {
        self.name = name
        self.hasPayload = hasPayload
        self.fields = fields
    }
}

/// One row: the state it belongs to, then one cell per action.
public struct RawRow {
    public let state: String
    public let cells: [RawCell]
    public init(_ state: String, _ cells: [RawCell]) {
        self.state = state
        self.cells = cells
    }
}

/// One cell, before validation.
public struct RawCell {
    public let kind: String
    public let target: String
    public let args: String
    public let effects: [String]
    public let child: String

    public init(
        _ kind: String, target: String = "", args: String = "",
        effects: [String] = [], child: String = ""
    ) {
        self.kind = kind
        self.target = target
        self.args = args
        self.effects = effects
        self.child = child
    }
}

/// A diagnostic, carrying the code from `spec/diagnostics.md`.
public struct TabularCenterError: Error, CustomStringConvertible {
    public let code: String
    public let message: String
    public var description: String { "\(code): \(message)" }
}

private func fail(_ code: String, _ message: String) throws -> Never {
    throw TabularCenterError(code: code, message: message)
}

public func buildDesc(_ raw: RawMachine) throws -> MachineDesc {
    let stateNames = raw.states.map(\.name)
    let actionNames = raw.actions.map(\.name)
    let effectNames = raw.effects.map(\.name)
    let payloadStates = Set(raw.states.filter(\.hasPayload).map(\.name))

    if !stateNames.contains(raw.initial) {
        try fail(
            "tabular-center::unknown-state",
            "initial state `\(raw.initial)` is not declared. "
                + "States: \(stateNames.joined(separator: " "))")
    }

    try validatePaths(raw, stateNames, actionNames)

    for (i, row) in raw.rows.enumerated() {
        guard i < stateNames.count else {
            try fail(
                "tabular-center::extra-row",
                "row `\(row.state)` does not correspond to a declared state. "
                    + "States: \(stateNames.joined(separator: " "))")
        }
        if row.state != stateNames[i] {
            try fail(
                "tabular-center::missing-row",
                "row \(i) is `\(row.state)` but `states` says `\(stateNames[i])`. "
                    + "Every state needs exactly one row, in declaration order. "
                    + "States: \(stateNames.joined(separator: " "))")
        }
    }
    if raw.rows.count < stateNames.count {
        try fail(
            "tabular-center::missing-row",
            "state `\(stateNames[raw.rows.count])` has no row. "
                + "Every state needs exactly one row, in declaration order. "
                + "States: \(stateNames.joined(separator: " "))")
    }

    var rows: [[CellDesc]] = []
    for row in raw.rows {
        guard row.cells.count == actionNames.count else {
            try fail(
                "tabular-center::row-arity",
                "row `\(row.state)` has \(row.cells.count) cells, expected "
                    + "\(actionNames.count). Expected columns: "
                    + actionNames.joined(separator: " "))
        }
        var out: [CellDesc] = []
        for (j, c) in row.cells.enumerated() {
            out.append(
                try cell(
                    raw, derive(c, row.state, actionNames[j], raw), row.state, actionNames[j],
                    effectNames: effectNames, stateNames: stateNames,
                    payloadStates: payloadStates))
        }
        rows.append(out)
    }

    let desc = MachineDesc(
        machine: raw.machine,
        stateType: raw.stateType,
        actionType: raw.actionType,
        effectType: raw.effectType,
        ctxType: raw.ctxType,
        initial: raw.initial,
        states: raw.states.map { Variant($0.name, hasPayload: $0.hasPayload, fields: $0.fields) },
        actions: raw.actions.map { Variant($0.name, hasPayload: $0.hasPayload, fields: $0.fields) },
        effects: raw.effects.map { Variant($0.name, hasPayload: $0.hasPayload, fields: $0.fields) },
        rows: rows,
        prototypeModifiers: raw.prototypeModifiers,
        children: raw.children,
        render: raw.render,
        hops: hopsOf(raw)
    )
    try checkMemberCollisions(desc)
    return desc
}

private func hopsOf(_ raw: RawMachine) -> [HopDesc] {
    let states = raw.states.map(\.name)
    let actions = raw.actions.map(\.name)
    var seen = Set<String>()
    var out: [HopDesc] = []
    for path in raw.paths {
        for hop in path.hops {
            guard let f = states.firstIndex(of: hop.from),
                  let a = actions.firstIndex(of: hop.action),
                  let t = states.firstIndex(of: hop.to),
                  seen.insert("\(f).\(a)").inserted
            else { continue }
            out.append(HopDesc(from: f, action: a, to: t))
        }
    }
    return out
}

private func checkMemberCollisions(_ d: MachineDesc) throws {
    var seen: [String: GeneratedMember] = [:]
    for m in cellsMembers(d) {
        if let first = seen[m.name] {
            try fail(
                "tabular-center::member-collision",
                "\(first.origin) and \(m.origin) would both generate the member `\(m.name)`. "
                    + "Rename a state, an action or an effect so the two differ."
            )
        }
        seen[m.name] = m
    }
}

private func cell(
    _ raw: RawMachine, _ c: RawCell, _ state: String, _ action: String,
    effectNames: [String], stateNames: [String], payloadStates: Set<String>
) throws -> CellDesc {
    func checkEffects() throws {
        for e in c.effects where !effectNames.contains(effectName(e)) {
            try fail(
                "tabular-center::unknown-effect",
                "cell (\(state), \(action)) emits `\(effectName(e))`, which is not a declared "
                    + "effect. Effects: \(effectNames.joined(separator: " "))")
        }
    }

    switch c.kind {
    case "IGNORE": return .ignore
    case "HANDLE": return .handle
    case "UNREACHABLE": return .unreachable

    case "GO":
        guard stateNames.contains(c.target) else {
            try fail(
                "tabular-center::unknown-state",
                "cell (\(state), \(action)) transitions to `\(c.target)`, which is not "
                    + "a declared state. States: \(stateNames.joined(separator: " "))")
        }
        if payloadStates.contains(c.target) && c.args.isEmpty {
            try fail(
                "tabular-center::go-target",
                "cell (\(state), \(action)) uses GO to `\(c.target)`, which carries a "
                    + "payload that cannot be derived from a literal. Use HANDLE, or "
                    + "supply literal arguments.")
        }
        try checkEffects()
        return .go(target: c.target, args: c.args, effects: c.effects)

    case "EMIT":
        guard !c.effects.isEmpty else {
            try fail(
                "tabular-center::empty-emit",
                "cell (\(state), \(action)) uses EMIT with no effects; use IGNORE or HANDLE")
        }
        try checkEffects()
        return .emit(effects: c.effects)

    case "DELEGATE":
        guard raw.children.contains(where: { $0.alias == c.child }) else {
            try fail(
                "tabular-center::unknown-child",
                "cell (\(state), \(action)) delegates to `\(c.child)`, which is not a "
                    + "declared child. Children: "
                    + raw.children.map(\.alias).joined(separator: " "))
        }
        return .delegate(child: c.child)

    default:
        try fail(
            "tabular-center::unknown-cell",
            "`\(c.kind)` in row `\(state)`, column `\(action)`. Expected one of: "
                + "IGNORE, HANDLE, UNREACHABLE, GO, EMIT, DELEGATE.")
    }
}

private func validatePaths(
    _ raw: RawMachine, _ stateNames: [String], _ actionNames: [String]
) throws {
    var seen = Set<String>()
    for path in raw.paths {
        if !seen.insert(path.name).inserted {
            try fail(
                "tabular-center::path-duplicate",
                "two paths are named `\(path.name)`; a narrowed call site names "
                    + "the path it narrows to, so names must be unique")
        }

        for state in path.states where !stateNames.contains(state) {
            try fail(
                "tabular-center::path-unknown-state",
                "path `\(path.name)` names state `\(state)`, which is not declared. "
                    + "States: \(stateNames.joined(separator: " "))")
        }

        if path.elements.count < 3 || path.elements.count % 2 == 0 {
            try fail(
                "tabular-center::path-broken",
                "path `\(path.name)` has \(path.elements.count) element(s); a path "
                    + "alternates state and action, starting and ending with a state, "
                    + "so the count is odd and at least three")
        }

        for hop in path.hops {
            guard let col = actionNames.firstIndex(of: hop.action) else {
                try fail(
                    "tabular-center::path-unknown-state",
                    "path `\(path.name)` names action `\(hop.action)`, which is not "
                        + "declared. Actions: \(actionNames.joined(separator: " "))")
                continue
            }
            let row = raw.rows.first { $0.state == hop.from }
            let cell = row?.cells.indices.contains(col) == true ? row?.cells[col] : nil
            let ok = cell.map { c in
                c.kind == "HANDLE" || c.kind == "DELEGATE"
                    || (c.kind == "GO" && c.target == hop.to)
            } ?? false
            if !ok {
                try fail(
                    "tabular-center::path-broken",
                    "path `\(path.name)` goes `\(hop.from)` -`\(hop.action)`-> "
                        + "`\(hop.to)`, and cell (\(hop.from), \(hop.action)) cannot "
                        + "reach `\(hop.to)`")
            }
        }

        if !path.back.isEmpty, !actionNames.contains(path.back) {
            try fail(
                "tabular-center::path-unknown-state",
                "path `\(path.name)` walks back by `\(path.back)`, which is not a "
                    + "declared action. Actions: \(actionNames.joined(separator: " "))")
        }

        if let last = path.states.last {
            let lastRow = raw.rows.first { $0.state == last }
            let leaves = lastRow?.cells.enumerated().contains { j, c in
                if !path.back.isEmpty, actionNames.indices.contains(j),
                    actionNames[j] == path.back
                {
                    return false
                }
                return c.kind == "HANDLE" || c.kind == "DELEGATE"
                    || (c.kind == "GO" && c.target != last)
            } ?? false
            if leaves {
                try fail(
                    "tabular-center::path-unterminated",
                    "path `\(path.name)` ends at `\(last)`, which can still be left; a "
                        + "path ends where the machine is done")
            }
        }
    }
}

private func derive(
    _ c: RawCell, _ state: String, _ action: String, _ raw: RawMachine
) -> RawCell {
    guard c.kind == "HANDLE" else { return c }
    for path in raw.paths {
        for hop in path.hops + path.reverseHops
        where hop.from == state && hop.action == action {
            return RawCell(
                "GO", target: hop.to, args: c.args,
                effects: c.effects, child: c.child)
        }
    }
    return c
}

public func effectName(_ ref: String) -> String {
    String(ref.prefix(while: { $0 != "(" }))
}
