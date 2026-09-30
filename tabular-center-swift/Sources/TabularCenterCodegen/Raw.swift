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

    /// States and actions, alternating, starting and ending with a state.
    /// See `spec/happy-paths.md`.
    public let elements: [String]

    /// The action that walks this path backwards, or "" if it has none.
    ///
    /// A wizard's "back" is the route again in the opposite order, and a wrong
    /// target there looks exactly like a right one. Named once here instead.
    public let back: String

    public init(name: String, elements: [String], back: String = "") {
        self.name = name
        self.elements = elements
        self.back = back
    }

    /// States, at the even positions.
    public var states: [String] {
        elements.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
    }

    /// Actions, at the odd positions -- one per hop.
    public var actions: [String] {
        elements.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
    }

    /// Hops, as `(from, action, to)`. Empty when the shape is wrong, so the
    /// shape check and the hop walk stay independent.
    public var hops: [(from: String, action: String, to: String)] {
        guard elements.count >= 3, elements.count % 2 == 1 else { return [] }
        return (0..<(elements.count / 2)).map {
            (elements[$0 * 2], elements[$0 * 2 + 1], elements[$0 * 2 + 2])
        }
    }

    /// The same hops walked backwards: `(to, back, from)`. Empty when no back
    /// action is named, which is why this changes nothing for a path without
    /// one.
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

    /// Declared happy paths, in declaration order. See `spec/happy-paths.md`.
    ///
    /// Defaulted to empty in the initialiser below, which is the feature's
    /// constraint expressed as a parameter: a machine without a spine is
    /// constructed exactly as before, and every existing caller compiles
    /// untouched.
    ///
    /// Read at generation time and discarded. Nothing here reaches `Table`, so
    /// a machine with a spine and the same machine written longhand produce
    /// byte-identical `TABLE`, `.grid`, `.lint`, `.cov` and `.mmd`.
    public let paths: [RawPath]
    /// See `MachineDesc.render`.
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
    /// Literal constructor arguments for `target`, e.g. `"(since: 0)"`.
    public let args: String
    /// The effects a static cell emits, as written, ARGUMENTS INCLUDED:
    /// `["stopClock"]`, or `["stopClock(reason: .cancelled)"]`. Use
    /// `effectName` for the part before `(`.
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
            "tabular-center::unknown-state",
            "initial state `\(raw.initial)` is not declared. "
                + "States: \(stateNames.joined(separator: " "))")
    }

    try validatePaths(raw, stateNames, actionNames)

    // Rows correspond to states one-to-one, in order. Position identifies a
    // row, so an out-of-order row is not a reordering — it is a row for the
    // wrong state.
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
        render: raw.render
    )
    try checkMemberCollisions(desc)
    return desc
}

/// `tabular-center::member-collision`: two things the generator would give
/// the same member name. See Kotlin's `checkMemberCollisions` for why it is
/// refused in both languages; here it would otherwise surface as an "invalid
/// redeclaration" in generated code, far from the matrix that caused it.
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
        // Rule R3. A GO cell is resolved entirely by the generator, so its
        // target must be constructible without developer code. Without this,
        // GO quietly becomes the lazy option and payloads fill with zero
        // values chosen to avoid writing a cell.
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

/// Reject a broken happy path before anything derives from it.
///
/// Errors before features: a default computed from an invalid spine is worse
/// than no default, because it produces a machine that compiles and goes
/// somewhere nobody wrote down.
///
/// The Kotlin twin is `validatePaths` in `tabular-center-kotlin/codegen/Raw.kt`, and the
/// messages are identical on purpose -- `spec/diagnostics.md` is normative for
/// both, and `diagnostics-coverage` fails if one emits a code the other does
/// not. See `spec/happy-paths.md`.
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

        // Shape before content. A route is a sequence of hops, and a hop is a
        // state, an action and a state, so the elements alternate and the
        // count is odd and at least three.
        if path.elements.count < 3 || path.elements.count % 2 == 0 {
            try fail(
                "tabular-center::path-broken",
                "path `\(path.name)` has \(path.elements.count) element(s); a path "
                    + "alternates state and action, starting and ending with a state, "
                    + "so the count is odd and at least three")
        }

        // A HANDLE counts as a connection. Its target is not knowable from the
        // matrix, and supplying that target is exactly what a path is for;
        // refusing it would reject the only cell kind this feature shortens.
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
            // THAT cell, not some cell in the row. Naming the action is what
            // makes this precise; a states-only spine could only ask whether
            // anything in the row reached `to`.
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

        // The back action, if there is one, is an action like any other.
        if !path.back.isEmpty, !actionNames.contains(path.back) {
            try fail(
                "tabular-center::path-unknown-state",
                "path `\(path.name)` walks back by `\(path.back)`, which is not a "
                    + "declared action. Actions: \(actionNames.joined(separator: " "))")
        }

        // A path that never ends is a loop with a name.
        //
        // Walking BACK is not leaving: a path with a `back` action is
        // travelled in both directions, so its own back column does not count
        // against the ending.
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

/// A `HANDLE` named by a hop becomes a `GO` to that hop's next state.
///
/// The half of `spec/happy-paths.md` that motivated the feature: on the happy
/// path the common case stops being typed. The Kotlin twin is `derive` in
/// `tabular-center-kotlin/codegen/Raw.kt`.
///
/// Only `HANDLE`. A `GO` already says where it goes, and rewriting it would let
/// a path silently contradict a cell -- the developer would have written two
/// answers and been told neither. `tabular-center::path-broken` rejects a hop whose
/// `GO` disagrees, so by the time this runs the two agree or the build stopped.
///
/// The result is indistinguishable from the longhand machine, which is the
/// additive test: a derived `GO(to)` and a written `GO(to)` are the same
/// `CellDesc`, so `TABLE`, `.grid`, `.lint`, `.cov` and `.mmd` are identical
/// either way.
///
/// Runs after `validatePaths`, so a hop is known to name a real cell before
/// anything is derived from it.
private func derive(
    _ c: RawCell, _ state: String, _ action: String, _ raw: RawMachine
) -> RawCell {
    guard c.kind == "HANDLE" else { return c }
    for path in raw.paths {
        // Forward hops first, then the reverse ones a `back` action declares.
        for hop in path.hops + path.reverseHops
        where hop.from == state && hop.action == action {
            // Constructed rather than copy-and-mutate: `RawCell`'s fields are
            // `let`, which is right for a value that represents what someone
            // wrote. The other fields come from `c` so a HANDLE carrying
            // effects keeps them.
            return RawCell(
                "GO", target: hop.to, args: c.args,
                effects: c.effects, child: c.child)
        }
    }
    return c
}

/// An effect reference without its arguments: `stopClock(reason: .cancelled)`
/// names the effect `stopClock`.
///
/// Which effect a cell emits is what validation and `TABLE` are about; with
/// what is the dispatcher's business, and it emits the reference verbatim.
public func effectName(_ ref: String) -> String {
    String(ref.prefix(while: { $0 != "(" }))
}
