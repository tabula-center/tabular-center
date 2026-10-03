import TabularCenter

/// Replays spec/conformance/step-algebra.cases against Swift's `Step`: each
/// case's input steps are built, the operation applied, and the result
/// written back in the file's spelling and compared as text. The file must
/// also hold every outcome combination for every operation, so losing a case
/// fails rather than passing on less. Format: spec/conformance/README.md.
enum AlgebraKind: String, CaseIterable, Comparable {
    case go = "Go", stay = "Stay", ignored = "Ignored"

    static func < (a: AlgebraKind, b: AlgebraKind) -> Bool { a.rawValue < b.rawValue }
}

enum AlgebraTarget {
    case literal(Int)
    case inputPlus(Int)
}

struct AlgebraWritten {
    let kind: AlgebraKind
    let targets: [AlgebraTarget]
    let effects: [String]
}

struct AlgebraError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

struct AlgebraCombination: Hashable {
    let op: String
    let lhs: AlgebraKind
    let rhs: AlgebraKind
}

func parseAlgebraTarget(_ text: String) throws -> AlgebraTarget {
    if text == "s" { return .inputPlus(0) }
    if text.hasPrefix("s+") {
        guard let offset = Int(text.dropFirst(2)) else { throw AlgebraError("bad target `\(text)`") }
        return .inputPlus(offset)
    }
    guard let value = Int(text) else { throw AlgebraError("bad target `\(text)`") }
    return .literal(value)
}

func parseAlgebraEffects(_ text: Substring) throws -> [String] {
    if text.isEmpty { return [] }
    guard text.hasPrefix("["), text.hasSuffix("]") else { throw AlgebraError("bad effects `\(text)`") }
    let inner = text.dropFirst().dropLast()
    if inner.isEmpty { throw AlgebraError("write no effects as nothing, not `[]`") }
    return inner.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
}

func parseAlgebraStep(_ text: String) throws -> AlgebraWritten {
    if text.hasPrefix("ignored") {
        guard text == "ignored" else { throw AlgebraError("`\(text)`: an ignored step has no effects") }
        return AlgebraWritten(kind: .ignored, targets: [], effects: [])
    }
    if text.hasPrefix("stay") {
        return AlgebraWritten(kind: .stay, targets: [], effects: try parseAlgebraEffects(text.dropFirst(4)))
    }
    guard text.hasPrefix("go(") else { throw AlgebraError("`\(text)` is not a step") }
    let rest = text.dropFirst(3)
    guard let close = rest.firstIndex(of: ")") else { throw AlgebraError("`\(text)`: unclosed target") }
    let targets = try rest[..<close].split(separator: ",").map { try parseAlgebraTarget(String($0)) }
    let effects = try parseAlgebraEffects(rest[rest.index(after: close)...])
    return AlgebraWritten(kind: .go, targets: targets, effects: effects)
}

func buildAlgebraStep(_ written: AlgebraWritten, input: Int) throws -> Step<Int, String> {
    switch written.kind {
    case .go:
        guard written.targets.count == 1 else { throw AlgebraError("an input step has exactly one target") }
        switch written.targets[0] {
        case let .literal(value): return .go(value, effects: written.effects)
        case let .inputPlus(offset): return .go(input + offset, effects: written.effects)
        }
    case .stay: return .stay(effects: written.effects)
    case .ignored: return .ignored
    }
}

func renderAlgebraStep<S>(_ step: Step<S, String>, _ target: (S) -> String) -> String {
    let head: String
    switch step {
    case let .go(next, _): head = "go(\(target(next)))"
    case .stay: head = "stay"
    case .ignored: head = "ignored"
    }
    return step.effects.isEmpty ? head : "\(head)[\(step.effects.joined(separator: ","))]"
}

func evaluateAlgebraCase(_ tokens: [String]) throws -> (String, String, AlgebraCombination) {
    if tokens.count == 4, tokens[0] == "map", tokens[2] == "=>" {
        let lhs = try parseAlgebraStep(tokens[1])
        let actual = try buildAlgebraStep(lhs, input: 0).map { $0 + 10 }
        let combination = AlgebraCombination(op: "map", lhs: lhs.kind, rhs: .go)
        return (renderAlgebraStep(actual) { String($0) }, tokens[3], combination)
    }
    if tokens.count == 6, tokens[0] == "and_then", tokens[2] == "then", tokens[4] == "=>" {
        let lhs = try parseAlgebraStep(tokens[1])
        let next = try parseAlgebraStep(tokens[3])
        _ = try buildAlgebraStep(next, input: 0)
        let actual = try buildAlgebraStep(lhs, input: 0).flatMap { s in
            try buildAlgebraStep(next, input: s)
        }
        let combination = AlgebraCombination(op: "and_then", lhs: lhs.kind, rhs: next.kind)
        return (renderAlgebraStep(actual) { String($0) }, tokens[5], combination)
    }
    if tokens.count == 5, tokens[0] == "zip", tokens[3] == "=>" {
        let lhs = try parseAlgebraStep(tokens[1])
        let rhs = try parseAlgebraStep(tokens[2])
        let actual = try buildAlgebraStep(lhs, input: 0).zip(try buildAlgebraStep(rhs, input: 0))
        let combination = AlgebraCombination(op: "zip", lhs: lhs.kind, rhs: rhs.kind)
        return (renderAlgebraStep(actual) { "\($0.0),\($0.1)" }, tokens[4], combination)
    }
    throw AlgebraError("not a case in the documented shape")
}

func requiredAlgebraCombinations() -> Set<AlgebraCombination> {
    var required = Set<AlgebraCombination>()
    for lhs in AlgebraKind.allCases {
        required.insert(AlgebraCombination(op: "map", lhs: lhs, rhs: .go))
        for rhs in AlgebraKind.allCases {
            required.insert(AlgebraCombination(op: "and_then", lhs: lhs, rhs: rhs))
            required.insert(AlgebraCombination(op: "zip", lhs: lhs, rhs: rhs))
        }
    }
    return required
}

func replayStepAlgebra(_ text: String) -> (cases: Int, failures: [String]) {
    var failures: [String] = []
    var seen = Set<AlgebraCombination>()
    var cases = 0
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    for (index, line) in lines.enumerated() {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if tokens.isEmpty { continue }
        cases += 1
        do {
            let (actual, expected, combination) = try evaluateAlgebraCase(tokens)
            seen.insert(combination)
            if actual != expected {
                failures.append("line \(index + 1): `\(tokens.joined(separator: " "))` gave \(actual), expected \(expected)")
            }
        } catch let error as AlgebraError {
            failures.append("line \(index + 1): \(error.message)")
        } catch {
            failures.append("line \(index + 1): \(error)")
        }
    }
    let missing = requiredAlgebraCombinations().subtracting(seen).sorted {
        ($0.op, $0.lhs, $0.rhs) < ($1.op, $1.lhs, $1.rhs)
    }
    for c in missing {
        failures.append("no case for \(c.op) with \(c.lhs.rawValue) and \(c.rhs.rawValue)")
    }
    return (cases, failures)
}
