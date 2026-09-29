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
    /// The rendering prototype, or nil for a machine without one. See
    /// `RenderDesc`. Nil is the default and emits nothing, so every machine
    /// declared before the rendering surface generates exactly what it did.
    public let render: RenderDesc?

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
        children: [ChildDesc] = [],
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
        self.render = render
    }
}

/// The rendering surface's prototype: `S -> UI`, declared separately from the
/// transition prototype. ARCHITECTURE §9, PLAN Phase 9b.
///
/// It generates one required member per STATE -- `renderIdle()`,
/// `renderRunning(_ state: Timer.Running)`, narrowed exactly as cells are --
/// and a `render` dispatcher that switches over every state with no
/// `default:`. Its color is its own: `modifiers` are split and placed as the
/// transition prototype's are (attributes before `func`, `async`/`throws`
/// after the parameters, `try await` at the call), and the two are
/// independent.
///
/// `returnType` is concrete. SwiftUI's `@ViewBuilder` returns `some View`,
/// which a protocol requirement cannot -- it needs an associated type -- so
/// that is a separate step (PLAN, Phase 9b), not something to approximate.
public struct RenderDesc: Equatable {
    /// Copied onto every render member and onto `render`.
    public let modifiers: [String]
    /// What a render member returns.
    public let returnType: String

    public init(modifiers: [String] = [], returnType: String = "Void") {
        self.modifiers = modifiers
        self.returnType = returnType
    }
}

/// One variant of a sum type.
///
/// `fields` exists only to feed `tabular-center::payload-hoist`, so it may be empty
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
