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
    public let prototypeModifiers: [String]
    public let children: [ChildDesc]
    public let render: RenderDesc?
    public let hops: [HopDesc]

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
        render: RenderDesc? = nil,
        hops: [HopDesc] = []
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
        self.hops = hops
    }
}

extension MachineDesc {
    public var withoutHops: MachineDesc {
        MachineDesc(
            machine: machine, stateType: stateType, actionType: actionType,
            effectType: effectType, ctxType: ctxType, initial: initial,
            states: states, actions: actions, effects: effects, rows: rows,
            prototypeModifiers: prototypeModifiers, children: children, render: render
        )
    }
}

/// One hop of a happy path, `from -action-> to`, as indices into
/// `MachineDesc.states` and `.actions`. spec/happy-paths.md, "Settled before
/// implementation": it generates a narrowed member taking the action that
/// ARRIVED in `from`, and an outcome enum with one case per state the `from`
/// row can produce -- `to` the happy one. The Kotlin twin is `HopDesc` in
/// `tabular-center-kotlin/codegen/Model.kt`.
public struct HopDesc: Equatable {
    public let from: Int
    public let action: Int
    public let to: Int

    public init(from: Int, action: Int, to: Int) {
        self.from = from
        self.action = action
        self.to = to
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
/// Two modes.
///
/// - **Concrete** (`builder` nil): every renderer returns `returnType`, and
///   so does `render`.
/// - **Builder** (`builder` set): SwiftUI's shape. A view is opaque, and a
///   protocol requirement cannot return `some View`, so each state gets an
///   associated type -- `associatedtype IdleBody: View` and
///   `@ViewBuilder func renderIdle() -> IdleBody` -- exactly as SwiftUI's own
///   `View` has `associatedtype Body` under `@ViewBuilder var body`. `render`
///   is generic over the conformer, `@ViewBuilder`, and returns
///   `some <conformance>`: the builder turns its `switch` into one view.
///   Opaque result types need macOS 10.15 / iOS 13 at runtime, so `render`
///   carries that `@available`; SwiftUI needs the same. `returnType` is
///   unused in this mode.
///
/// `builder` and `conformance` are names, not SwiftUI: the checks use a
/// stand-in builder, because SwiftUI does not exist on Linux.
public struct RenderDesc: Equatable {
    public let modifiers: [String]
    public let returnType: String
    public let builder: String?
    public let conformance: String

    public init(
        modifiers: [String] = [],
        returnType: String = "Void",
        builder: String? = nil,
        conformance: String = ""
    ) {
        self.modifiers = modifiers
        self.returnType = returnType
        self.builder = builder
        self.conformance = conformance
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
