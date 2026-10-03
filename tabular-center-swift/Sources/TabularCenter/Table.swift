/// A machine's transition matrix, emitted alongside the dispatcher.
///
/// Rows are states, columns are actions, both in declaration order — which is
/// what lets diagram export and the conformance runner agree on cell identity
/// across languages.
///
/// - `cell`: The cell at `(stateIndex, actionIndex)`.
/// - `stateIndex`: Row index of a state variant by name.
/// - `actionIndex`: Column index of an action variant by name.
/// - `coverage`: Counts by cell kind.
/// - `staticallyUnreached`: States no cell can statically transition into, excluding the initial one.
/// - `isFullyStatic`: Whether every cell is static, i.e.
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

    public func cell(_ state: Int, _ action: Int) -> Cell { cells[state][action] }

    public func stateIndex(_ name: String) -> Int? { states.firstIndex(of: name) }

    public func actionIndex(_ name: String) -> Int? { actions.firstIndex(of: name) }

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

    public func staticallyUnreached() -> [String] {
        let targets = Set(cells.flatMap { $0 }.compactMap(\.staticTarget))
        return states.filter { $0 != initial && !targets.contains($0) }
    }

    public func isFullyStatic() -> Bool { cells.flatMap { $0 }.allSatisfy(\.isStatic) }
}

/// Counts by cell kind, for the build-time coverage report.
///
/// - `total`: Total cells, i.e.
/// - `requiredMembers`: Cells the developer must implement.
/// - `ignorePercent`: Proportion of the matrix that is `ignore`, in percent.
/// - `unreachablePercent`: Proportion of the matrix that is `unreachable`, in percent.
public struct Coverage: Equatable {
    public let ignore: Int
    public let go: Int
    public let emit: Int
    public let handle: Int
    public let delegate: Int
    public let unreachable: Int

    public var total: Int { ignore + go + emit + handle + delegate + unreachable }

    public var requiredMembers: Int { handle + delegate }

    public var ignorePercent: Int { total == 0 ? 0 : ignore * 100 / total }

    public var unreachablePercent: Int { total == 0 ? 0 : unreachable * 100 / total }
}
