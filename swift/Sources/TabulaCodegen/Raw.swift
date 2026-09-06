/// The flat, stringly-typed shape a macro can fill in without judgement.
///
/// The macro is the one piece that needs swift-syntax, so it is the one piece
/// that stays hard to test. The remedy is to make it as small and as dumb as
/// possible: reading syntax nodes into strings is mechanical, while
/// *validating* those strings is where the decisions and the diagnostics live.
///
/// So the macro produces a `RawMachine` and calls `buildDesc`. Everything below
/// runs and is tested with no swift-syntax anywhere.
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
        children: [ChildDesc] = []
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
    /// Literal constructor arguments for `target`, e.g. `"(since: 0)"`.
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
public struct TabulaError: Error, CustomStringConvertible {
    public let code: String
    public let message: String
    public var description: String { "\(code): \(message)" }
}

private func fail(_ code: String, _ message: String) throws -> Never {
    throw TabulaError(code: code, message: message)
}

/// Validate a `RawMachine` and turn it into a `MachineDesc`.
///
/// Every diagnostic in `spec/diagnostics.md` that concerns the *declaration*
/// fires here, so each one has a test and none of them lives in the untestable
/// macro.
public func buildDesc(_ raw: RawMachine) throws -> MachineDesc {
    let stateNames = raw.states.map(\.name)
    let actionNames = raw.actions.map(\.name)
    let effectNames = raw.effects.map(\.name)
    let payloadStates = Set(raw.states.filter(\.hasPayload).map(\.name))

    if !stateNames.contains(raw.initial) {
        try fail(
            "tabula::unknown-state",
            "initial state `\(raw.initial)` is not declared. "
                + "States: \(stateNames.joined(separator: " "))")
    }

    // Rows correspond to states one-to-one, in order. Position identifies a
    // row, so an out-of-order row is not a reordering — it is a row for the
    // wrong state.
    for (i, row) in raw.rows.enumerated() {
        guard i < stateNames.count else {
            try fail(
                "tabula::extra-row",
                "row `\(row.state)` does not correspond to a declared state. "
                    + "States: \(stateNames.joined(separator: " "))")
        }
        if row.state != stateNames[i] {
            try fail(
                "tabula::missing-row",
                "row \(i) is `\(row.state)` but `states` says `\(stateNames[i])`. "
                    + "Every state needs exactly one row, in declaration order. "
                    + "States: \(stateNames.joined(separator: " "))")
        }
    }
    if raw.rows.count < stateNames.count {
        try fail(
            "tabula::missing-row",
            "state `\(stateNames[raw.rows.count])` has no row. "
                + "Every state needs exactly one row, in declaration order. "
                + "States: \(stateNames.joined(separator: " "))")
    }

    var rows: [[CellDesc]] = []
    for row in raw.rows {
        guard row.cells.count == actionNames.count else {
            try fail(
                "tabula::row-arity",
                "row `\(row.state)` has \(row.cells.count) cells, expected "
                    + "\(actionNames.count). Expected columns: "
                    + actionNames.joined(separator: " "))
        }
        var out: [CellDesc] = []
        for (j, c) in row.cells.enumerated() {
            out.append(
                try cell(
                    raw, c, row.state, actionNames[j],
                    effectNames: effectNames, stateNames: stateNames,
                    payloadStates: payloadStates))
        }
        rows.append(out)
    }

    return MachineDesc(
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
        children: raw.children
    )
}

private func cell(
    _ raw: RawMachine, _ c: RawCell, _ state: String, _ action: String,
    effectNames: [String], stateNames: [String], payloadStates: Set<String>
) throws -> CellDesc {
    func checkEffects() throws {
        for e in c.effects where !effectNames.contains(e) {
            try fail(
                "tabula::unknown-effect",
                "cell (\(state), \(action)) emits `\(e)`, which is not a declared "
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
                "tabula::unknown-state",
                "cell (\(state), \(action)) transitions to `\(c.target)`, which is not "
                    + "a declared state. States: \(stateNames.joined(separator: " "))")
        }
        // Rule R3. A GO cell is resolved entirely by the generator, so its
        // target must be constructible without developer code. Without this,
        // GO quietly becomes the lazy option and payloads fill with zero
        // values chosen to avoid writing a cell.
        if payloadStates.contains(c.target) && c.args.isEmpty {
            try fail(
                "tabula::go-target",
                "cell (\(state), \(action)) uses GO to `\(c.target)`, which carries a "
                    + "payload that cannot be derived from a literal. Use HANDLE, or "
                    + "supply literal arguments.")
        }
        try checkEffects()
        return .go(target: c.target, args: c.args, effects: c.effects)

    case "EMIT":
        guard !c.effects.isEmpty else {
            try fail(
                "tabula::empty-emit",
                "cell (\(state), \(action)) uses EMIT with no effects; use IGNORE or HANDLE")
        }
        try checkEffects()
        return .emit(effects: c.effects)

    case "DELEGATE":
        guard raw.children.contains(where: { $0.alias == c.child }) else {
            try fail(
                "tabula::unknown-child",
                "cell (\(state), \(action)) delegates to `\(c.child)`, which is not a "
                    + "declared child. Children: "
                    + raw.children.map(\.alias).joined(separator: " "))
        }
        return .delegate(child: c.child)

    default:
        try fail(
            "tabula::unknown-cell",
            "`\(c.kind)` in row `\(state)`, column `\(action)`. Expected one of: "
                + "IGNORE, HANDLE, UNREACHABLE, GO, EMIT, DELEGATE.")
    }
}
