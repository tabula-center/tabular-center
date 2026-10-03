/// The outcome of one matrix cell.
///
/// `stay` and `ignored` are behaviourally identical and deliberately distinct:
/// `ignored` means *the developer asserts this action is not applicable in
/// this state*; `stay` means *the developer handled it and chose not to move*.
/// The lints and the coverage report treat them differently, so collapsing
/// them would lose real information.
///
/// A step is a value, and it composes (spec/cells.md 6):
///
/// - `map(_:)` applies its closure to a `.go` target; `.stay` and `.ignored`
///   pass through.
/// - `flatMap(_:)` runs its closure on a `.go` target and returns the
///   closure's step, with this step's effects followed by the closure's.
///   `.stay` and `.ignored` short-circuit without calling it. An `.ignored`
///   from the closure absorbs: the result is `.ignored`, with no effects.
/// - `zip(_:with:)` is `flatMap { x in other.map { y in transform(x, y) } }`,
///   and `zip(_:)` pairs the targets. When this step is not `.go`, `other`'s
///   effects are dropped.
///
/// ```swift
/// func enter(_ s: S) -> Step<S, F> {
///     s == .validating ? .go(s, effects: [.fetch]) : .go(s, effects: [])
/// }
/// Step<S, F>.go(.validating, effects: [.log]).flatMap(enter)
/// // .go(.validating, effects: [.log, .fetch])
/// ```
///
/// Every closure may throw; the operations rethrow.
///
/// - `go`: Transition to the associated state.
/// - `stay`: Handled; remain in the current state.
/// - `ignored`: Not applicable in this state; nothing happened.
/// - `effects`: Effects emitted, in order.
/// - `target`: The target state, if this step transitions.
/// - `isIgnored`: Whether the cell declared the action inapplicable.
/// - `isTransition`: Whether the cell transitioned.
/// - `mapEffects`: Relabel the effects, keeping the outcome.
public enum Step<S, F> {
    case go(S, effects: [F])
    case stay(effects: [F])
    case ignored
}

extension Step {
    public var effects: [F] {
        switch self {
        case let .go(_, effects): return effects
        case let .stay(effects): return effects
        case .ignored: return []
        }
    }

    public var target: S? {
        if case let .go(next, _) = self { return next }
        return nil
    }

    public var isIgnored: Bool {
        if case .ignored = self { return true }
        return false
    }

    public var isTransition: Bool {
        if case .go = self { return true }
        return false
    }

    public func map<T>(_ transform: (S) throws -> T) rethrows -> Step<T, F> {
        switch self {
        case let .go(next, effects): return .go(try transform(next), effects: effects)
        case let .stay(effects): return .stay(effects: effects)
        case .ignored: return .ignored
        }
    }

    @available(*, deprecated, renamed: "map")
    public func mapState<T>(_ transform: (S) -> T) -> Step<T, F> {
        map(transform)
    }

    public func flatMap<T>(_ transform: (S) throws -> Step<T, F>) rethrows -> Step<T, F> {
        switch self {
        case let .go(next, effects):
            switch try transform(next) {
            case let .go(then, more): return .go(then, effects: effects + more)
            case let .stay(more): return .stay(effects: effects + more)
            case .ignored: return .ignored
            }
        case let .stay(effects): return .stay(effects: effects)
        case .ignored: return .ignored
        }
    }

    public func zip<T, U>(
        _ other: Step<T, F>, with transform: (S, T) throws -> U
    ) rethrows -> Step<U, F> {
        try flatMap { x in try other.map { y in try transform(x, y) } }
    }

    public func zip<T>(_ other: Step<T, F>) -> Step<(S, T), F> {
        self.zip(other) { ($0, $1) }
    }

    public func mapEffects<G>(_ transform: (F) -> G) -> Step<S, G> {
        switch self {
        case let .go(next, effects): return .go(next, effects: effects.map(transform))
        case let .stay(effects): return .stay(effects: effects.map(transform))
        case .ignored: return .ignored
        }
    }
}

extension Step: Equatable where S: Equatable, F: Equatable {}
