/// The outcome of one matrix cell.
///
/// `stay` and `ignored` are behaviourally identical and deliberately distinct:
/// `ignored` means *the developer asserts this action is not applicable in
/// this state*; `stay` means *the developer handled it and chose not to move*.
/// The lints and the coverage report treat them differently, so collapsing
/// them would lose real information.
public enum Step<S, F> {
    /// Transition to the associated state.
    case go(S, effects: [F])
    /// Handled; remain in the current state.
    case stay(effects: [F])
    /// Not applicable in this state; nothing happened.
    case ignored
}

extension Step {
    /// Effects emitted, in order.
    public var effects: [F] {
        switch self {
        case let .go(_, effects): return effects
        case let .stay(effects): return effects
        case .ignored: return []
        }
    }

    /// The target state, if this step transitions.
    public var target: S? {
        if case let .go(next, _) = self { return next }
        return nil
    }

    /// Whether the cell declared the action inapplicable.
    public var isIgnored: Bool {
        if case .ignored = self { return true }
        return false
    }

    /// Whether the cell transitioned.
    public var isTransition: Bool {
        if case .go = self { return true }
        return false
    }

    /// Relabel the target state, keeping effects. Composition primitive.
    public func mapState<T>(_ transform: (S) -> T) -> Step<T, F> {
        switch self {
        case let .go(next, effects): return .go(transform(next), effects: effects)
        case let .stay(effects): return .stay(effects: effects)
        case .ignored: return .ignored
        }
    }

    /// Relabel the effects, keeping the outcome.
    ///
    /// Composition primitive: a `DELEGATE` cell lifts a child's effects into
    /// the parent's vocabulary with this.
    public func mapEffects<G>(_ transform: (F) -> G) -> Step<S, G> {
        switch self {
        case let .go(next, effects): return .go(next, effects: effects.map(transform))
        case let .stay(effects): return .stay(effects: effects.map(transform))
        case .ignored: return .ignored
        }
    }
}

extension Step: Equatable where S: Equatable, F: Equatable {}
