/// One entry in the transition matrix, as inert data.
///
/// Six kinds, split three and three. The *static* kinds (`ignore`, `go`,
/// `emit`) are resolved entirely by the generator and produce no required
/// member. This is what makes a large matrix survivable: the boring 60-70% of
/// cells that just mean "not applicable here" cost one word each.
///
/// - `ignore`: No-op.
/// - `go`: Unconditional transition.
/// - `emit`: Remain in the current state, emitting the listed effects.
/// - `handle`: Generates a required member; the developer writes the body.
/// - `delegate`: Forward to a composed child machine.
/// - `unreachable`: The developer asserts this pair cannot occur; traps.
/// - `isStatic`: Whether the generator resolves this cell entirely, with no developer code.
/// - `generatesMember`: Whether this cell contributes a required member.
/// - `staticTarget`: The target state variant, if this cell transitions unconditionally.
/// - `staticEffects`: Effects this cell emits unconditionally.
/// - `kindName`: Lowercase kind name, as used in diagnostics and the conformance format.
public enum Cell: Equatable {
    case ignore

    case go(target: String, effects: [String])

    case emit(effects: [String])

    case handle

    case delegate(child: String)

    case unreachable
}

extension Cell {
    public var isStatic: Bool {
        switch self {
        case .ignore, .go, .emit: return true
        case .handle, .delegate, .unreachable: return false
        }
    }

    public var generatesMember: Bool {
        switch self {
        case .handle, .delegate: return true
        case .ignore, .go, .emit, .unreachable: return false
        }
    }

    public var staticTarget: String? {
        if case let .go(target, _) = self { return target }
        return nil
    }

    public var staticEffects: [String] {
        switch self {
        case let .go(_, effects): return effects
        case let .emit(effects): return effects
        default: return []
        }
    }

    public var kindName: String {
        switch self {
        case .ignore: return "ignore"
        case .go: return "go"
        case .emit: return "emit"
        case .handle: return "handle"
        case .delegate: return "delegate"
        case .unreachable: return "unreachable"
        }
    }
}
