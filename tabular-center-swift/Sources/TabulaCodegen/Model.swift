/// The machine description a generator emits from.
///
/// ## Why this is a separate module
///
/// A Swift macro implementation must link swift-syntax, which is a **remote
/// package dependency**. `nix flake check` builds with no network, so adding
/// swift-syntax to this package would break every Swift check — not just the
/// macro's.
///
/// So the generator is split the same way the Kotlin one is:
///
/// - **This module** turns a `MachineDesc` into Swift source. Pure, no
///   swift-syntax, no network, fully testable.
/// - **The macro** (not yet written) parses syntax into a `MachineDesc` and
///   calls `emit`. Mechanical, and small enough to review by eye.
///
/// The split is worth keeping after swift-syntax is available. A code generator
/// whose logic can only be exercised through a compiler plugin is a generator
/// nobody refactors — and here it is also the difference between a Swift
/// toolchain problem breaking one check and breaking all of them.
public struct MachineDesc {
    public let machine: String
    public let stateType: String
    public let actionType: String
    public let effectType: String
    public let ctxType: String
    public let initial: String
    public let states: [Variant]
    public let actions: [Variant]
    public let effects: [Variant]
    public let rows: [[CellDesc]]
    /// Copied verbatim onto every generated member. See ARCHITECTURE §5.
    public let prototypeModifiers: [String]
    /// Child machines reached by `delegate`, in first-appearance order.
    public let children: [ChildDesc]

    public init(
        machine: String,
        stateType: String,
        actionType: String,
        effectType: String,
        ctxType: String,
        initial: String,
        states: [Variant],
        actions: [Variant],
        effects: [Variant],
        rows: [[CellDesc]],
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

/// One variant of a sum type.
///
/// `fields` exists only to feed `tabula::payload-hoist`, so it may be empty
/// even when `hasPayload` is true — a generator that cannot resolve a type
/// still produces a usable machine, just without that one lint.
public struct Variant {
    public let name: String
    public let hasPayload: Bool
    public let fields: [(name: String, type: String)]

    public init(_ name: String, hasPayload: Bool = false, fields: [(name: String, type: String)] = []) {
        self.name = name
        self.hasPayload = hasPayload
        self.fields = fields
    }
}

/// A child machine referenced by one or more `delegate` cells.
public struct ChildDesc {
    public let alias: String
    public let stateType: String
    public let actionType: String
    public let effectType: String
    public let ctxType: String

    public init(alias: String, stateType: String, actionType: String, effectType: String, ctxType: String) {
        self.alias = alias
        self.stateType = stateType
        self.actionType = actionType
        self.effectType = effectType
        self.ctxType = ctxType
    }
}

/// One cell, as the generator sees it.
public enum CellDesc: Equatable {
    case ignore
    case handle
    case unreachable
    case go(target: String, args: String, effects: [String])
    case emit(effects: [String])
    case delegate(child: String)
}
