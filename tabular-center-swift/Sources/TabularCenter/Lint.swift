// - `ignoreHeavyPercent`: Percentage of `ignore` cells above which `ignoreHeavy` fires.
// - `unreachableHeavyPercent`: Percentage of `unreachable` cells above which `unreachableHeavy` fires.
// - `payloadHoistStates`: Number of states a payload field must appear in before `payloadHoist` fires.
// - `canonicalType`: Fields repeated across `payloadHoistStates` or more states.
// - `lint`: Every finding for a machine, in a stable order.
// - `report`: Findings rendered one per line, prefixed with the machine name.

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
///
/// - `noStaticEntry`: Nothing can transition into this state, in a fully static matrix.
/// - `noStaticExit`: No cell in this row can statically leave it.
/// - `deadRow`: Every cell in this row ignores.
/// - `deadColumn`: No state responds to this action.
/// - `ignoreHeavy`: The matrix is overwhelmingly `ignore`.
/// - `unreachableHeavy`: `unreachable` occupies a large share of the matrix.
/// - `payloadHoist`: The same payload field appears in several states.
/// - `code`: Stable diagnostic code, matching `spec/diagnostics.md`.
/// - `message`: Human-readable message, remedy included.
public enum Finding: Equatable {
    case noStaticEntry(state: String)
    case noStaticExit(state: String)
    case deadRow(state: String)
    case deadColumn(action: String)
    case ignoreHeavy(percent: Int)
    case unreachableHeavy(count: Int, percent: Int)
    case payloadHoist(field: String, type: String, states: [String])
}

extension Finding {
    public var code: String {
        switch self {
        case .noStaticEntry: return "tabular-center::no-static-entry"
        case .noStaticExit: return "tabular-center::no-static-exit"
        case .deadRow: return "tabular-center::dead-row"
        case .deadColumn: return "tabular-center::dead-column"
        case .ignoreHeavy: return "tabular-center::ignore-heavy"
        case .unreachableHeavy: return "tabular-center::unreachable-heavy"
        case .payloadHoist: return "tabular-center::payload-hoist"
        }
    }

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

public let ignoreHeavyPercent = 70

public let unreachableHeavyPercent = 25

public let payloadHoistStates = 3

/// State payload fields, as `(state, field, type)` in declaration order.
public typealias Payloads = [(state: String, field: String, type: String)]

public func canonicalType(_ type: String) -> String {
    switch type {
    case "Int", "Int8", "Int16", "Int32", "Int64",
         "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
        return "int"
    case "Float", "Double": return "float"
    case "Bool": return "bool"
    case "String", "Substring": return "string"
    case "Character": return "char"
    default: return type
    }
}

public func payloadHoist(_ payloads: Payloads) -> [Finding] {
    var seen: [String] = []
    var out: [Finding] = []
    for entry in payloads {
        let type = canonicalType(entry.type)
        let key = "\(entry.field)\u{0}\(type)"
        if seen.contains(key) { continue }
        seen.append(key)
        let states = payloads
            .filter { $0.field == entry.field && canonicalType($0.type) == type }
            .map { $0.state }
        if states.count >= payloadHoistStates {
            out.append(.payloadHoist(field: entry.field, type: type, states: states))
        }
    }
    return out
}

public func lint(_ t: Table) -> [Finding] {
    var out: [Finding] = []

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

public func report(_ t: Table, payloads: Payloads = []) -> String {
    (lint(t) + payloadHoist(payloads))
        .map { "warning[\($0.code)]: \(t.machine): \($0.message)\n" }
        .joined()
}
