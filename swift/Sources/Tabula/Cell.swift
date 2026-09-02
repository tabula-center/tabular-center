/// One entry in the transition matrix, as inert data.
///
/// Six kinds, split three and three. The *static* kinds (`ignore`, `go`,
/// `emit`) are resolved entirely by the generator and produce no required
/// member. This is what makes a large matrix survivable: the boring 60-70% of
/// cells that just mean "not applicable here" cost one word each.
public enum Cell: Equatable {
    /// No-op. The action is not applicable in this state.
    case ignore

    /// Unconditional transition. The target must be statically constructible:
    /// payload-free, or built from literals. See ARCHITECTURE rule R3.
    case go(target: String, effects: [String])

    /// Remain in the current state, emitting the listed effects.
    case emit(effects: [String])

    /// Generates a required member; the developer writes the body.
    case handle

    /// Forward to a composed child machine.
    ///
    /// Written out explicitly, one cell at a time: a parent never inherits
    /// coverage wholesale from a child.
    case delegate(child: String)

    /// The developer asserts this pair cannot occur; traps.
    ///
    /// Generates no member — writing `UNREACHABLE` *is* the statement of
    /// intent — but the coverage report counts them, because a machine with
    /// many usually has a modelling error.
    case unreachable
}

extension Cell {
    /// Whether the generator resolves this cell entirely, with no developer
    /// code.
    public var isStatic: Bool {
        switch self {
        case .ignore, .go, .emit: return true
        case .handle, .delegate, .unreachable: return false
        }
    }

    /// Whether this cell contributes a required member.
    ///
    /// Sum it over the matrix and you have the number of things the developer
    /// must implement. This is the predicate the guarantee rests on.
    public var generatesMember: Bool {
        switch self {
        case .handle, .delegate: return true
        case .ignore, .go, .emit, .unreachable: return false
        }
    }

    /// The target state variant, if this cell transitions unconditionally.
    public var staticTarget: String? {
        if case let .go(target, _) = self { return target }
        return nil
    }

    /// Effects this cell emits unconditionally.
    public var staticEffects: [String] {
        switch self {
        case let .go(_, effects): return effects
        case let .emit(effects): return effects
        default: return []
        }
    }

    /// Lowercase kind name, as used in diagnostics and the conformance format.
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
