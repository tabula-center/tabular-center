/// A machine's transition matrix, emitted alongside the dispatcher.
///
/// Rows are states, columns are actions, both in declaration order — which is
/// what lets diagram export and the conformance runner agree on cell identity
/// across languages.
public struct Table: Equatable {
    public let machine: String
    public let states: [String]
    public let actions: [String]
    public let cells: [[Cell]]
    public let initial: String?

    public init(
        machine: String,
        states: [String],
        actions: [String],
        cells: [[Cell]],
        initial: String? = nil
    ) {
        self.machine = machine
        self.states = states
        self.actions = actions
        self.cells = cells
        self.initial = initial
    }

    /// The cell at `(stateIndex, actionIndex)`.
    public func cell(_ state: Int, _ action: Int) -> Cell { cells[state][action] }

    /// Row index of a state variant by name.
    public func stateIndex(_ name: String) -> Int? { states.firstIndex(of: name) }

    /// Column index of an action variant by name.
    public func actionIndex(_ name: String) -> Int? { actions.firstIndex(of: name) }

    /// Counts by cell kind.
    public func coverage() -> Coverage {
        let flat = cells.flatMap { $0 }
        return Coverage(
            ignore: flat.filter { if case .ignore = $0 { return true } else { return false } }.count,
            go: flat.filter { if case .go = $0 { return true } else { return false } }.count,
            emit: flat.filter { if case .emit = $0 { return true } else { return false } }.count,
            handle: flat.filter { if case .handle = $0 { return true } else { return false } }.count,
            delegate: flat.filter { if case .delegate = $0 { return true } else { return false } }.count,
            unreachable: flat.filter {
                if case .unreachable = $0 { return true } else { return false }
            }.count
        )
    }

    /// States no cell can statically transition into, excluding the initial
    /// one.
    ///
    /// Only static targets are knowable at build time, so a state reached
    /// solely from a `handle` cell appears here. That is why the reachability
    /// lint is gated on `isFullyStatic`.
    public func staticallyUnreached() -> [String] {
        let targets = Set(cells.flatMap { $0 }.compactMap(\.staticTarget))
        return states.filter { $0 != initial && !targets.contains($0) }
    }

    /// Whether every cell is static, i.e. whether reachability is knowable.
    public func isFullyStatic() -> Bool { cells.flatMap { $0 }.allSatisfy(\.isStatic) }
}

/// Counts by cell kind, for the build-time coverage report.
public struct Coverage: Equatable {
    public let ignore: Int
    public let go: Int
    public let emit: Int
    public let handle: Int
    public let delegate: Int
    public let unreachable: Int

    /// Total cells, i.e. states x actions.
    public var total: Int { ignore + go + emit + handle + delegate + unreachable }

    /// Cells the developer must implement.
    ///
    /// `unreachable` is excluded: writing it *is* the implementation.
    public var requiredMembers: Int { handle + delegate }

    /// Proportion of the matrix that is `ignore`, in percent.
    public var ignorePercent: Int { total == 0 ? 0 : ignore * 100 / total }

    /// Proportion of the matrix that is `unreachable`, in percent.
    public var unreachablePercent: Int { total == 0 ? 0 : unreachable * 100 / total }
}
