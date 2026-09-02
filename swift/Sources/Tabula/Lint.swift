/// Findings computable from a machine's table.
///
/// Everything here is a **warning**, never an error. Each rule is a judgement
/// call with legitimate exceptions, and a lint that fails a build on a
/// judgement call teaches people to disable lints.
///
/// Two rules govern the set, learned while writing the Rust version:
///
/// - A lint that fires on healthy machines is a lint people turn off.
///   `noStaticEntry` reports only for a fully static matrix; `unreachableHeavy`
///   fires on a concentration, not on the one or two deliberate assertions the
///   cell kind exists for.
/// - Two warnings for one problem is noise. `deadRow` subsumes `noStaticExit`.
public enum Finding: Equatable {
    /// Nothing can transition into this state, in a fully static matrix.
    case noStaticEntry(state: String)
    /// No cell in this row can statically leave it.
    case noStaticExit(state: String)
    /// Every cell in this row ignores.
    case deadRow(state: String)
    /// No state responds to this action.
    case deadColumn(action: String)
    /// The matrix is overwhelmingly `ignore`.
    case ignoreHeavy(percent: Int)
    /// `unreachable` occupies a large share of the matrix.
    case unreachableHeavy(count: Int, percent: Int)
    /// The same payload field appears in several states.
    case payloadHoist(field: String, type: String, states: [String])
}

extension Finding {
    /// Stable diagnostic code, matching `spec/diagnostics.md`.
    public var code: String {
        switch self {
        case .noStaticEntry: return "tabula::no-static-entry"
        case .noStaticExit: return "tabula::no-static-exit"
        case .deadRow: return "tabula::dead-row"
        case .deadColumn: return "tabula::dead-column"
        case .ignoreHeavy: return "tabula::ignore-heavy"
        case .unreachableHeavy: return "tabula::unreachable-heavy"
        case .payloadHoist: return "tabula::payload-hoist"
        }
    }

    /// Human-readable message, remedy included.
    public var message: String {
        switch self {
        case let .noStaticEntry(state):
            return "nothing can transition into `\(state)`; every cell in this matrix is "
                + "static, so it is genuinely unreachable"
        case let .noStaticExit(state):
            return "no cell in row `\(state)` can leave it statically; confirm this state "
                + "is meant to be terminal"
        case let .deadRow(state):
            return "every cell in row `\(state)` ignores; confirm this state is meant to "
                + "be terminal"
        case let .deadColumn(action):
            return "no state responds to `\(action)`; the action is dead or a row was missed"
        case let .ignoreHeavy(percent):
            return "\(percent)% of cells are IGNORE; consider splitting this machine"
        case let .unreachableHeavy(count, percent):
            return "\(count) UNREACHABLE cells (\(percent)% of the matrix); a concentration "
                + "this high usually means the alphabet is wrong"
        case let .payloadHoist(field, type, states):
            return "`\(field): \(type)` appears in the payloads of "
                + "\(states.joined(separator: ", ")); consider hoisting it to Context"
        }
    }
}

/// Percentage of `ignore` cells above which `ignoreHeavy` fires.
public let ignoreHeavyPercent = 70

/// Percentage of `unreachable` cells above which `unreachableHeavy` fires.
public let unreachableHeavyPercent = 25

/// Number of states a payload field must appear in before `payloadHoist`
/// fires. Two is a coincidence; three is a pattern.
public let payloadHoistStates = 3

/// State payload fields, as `(state, field, type)` in declaration order.
public typealias Payloads = [(state: String, field: String, type: String)]

/// Fields repeated across `payloadHoistStates` or more states.
public func payloadHoist(_ payloads: Payloads) -> [Finding] {
    var seen: [String] = []
    var out: [Finding] = []
    for entry in payloads {
        let key = "\(entry.field)\u{0}\(entry.type)"
        if seen.contains(key) { continue }
        seen.append(key)
        // A closure, not `map(\.state)`: Swift has no key paths to tuple
        // members, and the error it gives says something else entirely.
        let states = payloads
            .filter { $0.field == entry.field && $0.type == entry.type }
            .map { $0.state }
        if states.count >= payloadHoistStates {
            out.append(.payloadHoist(field: entry.field, type: entry.type, states: states))
        }
    }
    return out
}

/// Every finding for a machine, in a stable order.
public func lint(_ t: Table) -> [Finding] {
    var out: [Finding] = []

    // Only meaningful when every cell is static; otherwise a `handle` cell
    // could reach anything and the rule would be guessing.
    if t.isFullyStatic() {
        out.append(contentsOf: t.staticallyUnreached().map { Finding.noStaticEntry(state: $0) })
    }

    for (i, row) in t.cells.enumerated() {
        if row.allSatisfy({ if case .ignore = $0 { return true } else { return false } }) {
            out.append(.deadRow(state: t.states[i]))
            continue
        }
        if !row.contains(where: { $0.staticTarget != nil || !$0.isStatic }) {
            out.append(.noStaticExit(state: t.states[i]))
        }
    }

    for (j, action) in t.actions.enumerated() {
        let dead = t.cells.allSatisfy { row in
            if case .ignore = row[j] { return true } else { return false }
        }
        if dead { out.append(.deadColumn(action: action)) }
    }

    let c = t.coverage()
    if c.ignorePercent >= ignoreHeavyPercent { out.append(.ignoreHeavy(percent: c.ignorePercent)) }
    if c.unreachablePercent >= unreachableHeavyPercent {
        out.append(.unreachableHeavy(count: c.unreachable, percent: c.unreachablePercent))
    }
    return out
}

/// Findings rendered one per line, prefixed with the machine name.
public func report(_ t: Table, payloads: Payloads = []) -> String {
    (lint(t) + payloadHoist(payloads))
        .map { "warning[\($0.code)]: \(t.machine): \($0.message)\n" }
        .joined()
}
