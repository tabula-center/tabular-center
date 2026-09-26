import Tabula

/// Parses `spec/conformance` — the same `.tbl` and `.trace` files the Rust and
/// Kotlin harnesses read.
///
/// Published as **TabulaTesting**, separately from the runtime: a machine in
/// production has no use for a fixture parser, and a test dependency that ships
/// to users is a test dependency nobody removes later.
///
/// A third parser rather than a shared one, deliberately. The format was chosen
/// to parse in about sixty lines precisely so each language could own its
/// parser with no dependency; three small parsers that agree are worth more
/// than one that no language can build offline.

/// A cell as the fixture declares it.
public enum CellSpec: Equatable {
    case ignore
    case handle
    case unreachable
    case go(target: String, effects: [String])
    case emit(effects: [String])
    case delegate(child: String)

    /// Rendered the way the fixture writes it, for diagnostics.
    public var text: String {
        switch self {
        case .ignore: return "IGNORE"
        case .handle: return "HANDLE"
        case .unreachable: return "UNREACHABLE"
        case let .go(target, effects):
            return effects.isEmpty
                ? "GO(\(target))"
                : "GO(\(target), \(effects.joined(separator: ", ")))"
        case let .emit(effects): return "EMIT(\(effects.joined(separator: ", ")))"
        case let .delegate(child): return "DELEGATE(\(child))"
        }
    }
}

/// A parsed `.tbl` fixture.
public struct Spec {
    public let machine: String
    public let initial: String
    public let states: [String]
    public let actions: [String]
    public let cells: [[CellSpec]]
}

/// What a trace step expects.
public enum Expect: Equatable {
    case go(state: String, fields: [String: Int])
    case stay
    case ignored
}

/// One line of a trace.
public struct TraceStep {
    public let action: String
    public let args: [String: Int]
    public let expect: Expect
    public let effects: [String]
}

/// A parsed `.trace` block.
public struct Trace {
    public var name: String
    public var ctx: [String: Int] = [:]
    public var from: String = ""
    /// Payload fields of the starting state. `go` accepted these from the
    /// start and `from` did not, which silently began a composition trace in
    /// the wrong child state. The two must stay symmetric.
    public var fromFields: [String: Int] = [:]
    public var steps: [TraceStep] = []
}

/// Anything wrong with a fixture.
public struct SpecError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
    public init(_ message: String) { self.message = message }
}

/// Reduce an effect or state rendering to its bare variant name.
///
/// Three shapes must all land on `StopClock`: the fixture's own `StopClock`, a
/// qualified `F.StopClock`, and a Swift enum description like
/// `stopClock(reason: elapsed)`.
///
/// **Order matters.** Taking the last path segment first breaks on the third,
/// because the payload may contain a separator. Strip the payload, then split
/// the path. Rust learned this from four conformance failures and Kotlin
/// inherited the fix; this is the same rule a third time.
public func lastSegment(_ s: String) -> String {
    let cut = s.firstIndex { $0 == "(" || $0 == "{" || $0 == " " }
    let head = cut.map { String(s[s.startIndex..<$0]) } ?? s
    let afterDot = head.split(separator: ".").last.map(String.init) ?? head
    let afterColon = afterDot.split(separator: ":").last.map(String.init) ?? afterDot
    return trim(afterColon)
}

/// Stdlib-only helpers.
///
/// `trimmingCharacters(in:)` and `components(separatedBy:)` are Foundation,
/// and this is a published library: importing Foundation to trim a string
/// would put the whole of it on every consumer's link line. The runner may
/// import it — it needs file IO — but the library should not.
private func trim(_ s: String) -> String {
    var t = Substring(s)
    while let f = t.first, f == " " || f == "\t" { t = t.dropFirst() }
    while let l = t.last, l == " " || l == "\t" { t = t.dropLast() }
    return String(t)
}

/// Split on the first `=>`. Written out because `range(of:)` is Foundation and
/// `firstRange(of:)` is newer than the tools-version this package declares.
private func splitOnArrow(_ s: String) -> (String, String)? {
    let chars = Array(s)
    var i = 0
    while i + 1 < chars.count {
        if chars[i] == "=", chars[i + 1] == ">" {
            return (String(chars[0..<i]), String(chars[(i + 2)...]))
        }
        i += 1
    }
    return nil
}

private func strip(_ line: Substring) -> String {
    let noComment = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
    return trim(String(noComment))
}

private func words(_ s: String) -> [String] {
    s.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
}

private func parseCell(_ text: String, _ at: String) throws -> CellSpec {
    let t = trim(text)
    func inner(_ prefix: String) -> [String]? {
        guard t.hasPrefix(prefix), t.hasSuffix(")") else { return nil }
        let body = t.dropFirst(prefix.count).dropLast()
        return body.split(separator: ",")
            .map { trim(String($0)) }
            .filter { !$0.isEmpty }
    }

    switch t {
    case "IGNORE": return .ignore
    case "HANDLE": return .handle
    case "UNREACHABLE": return .unreachable
    default: break
    }
    if let parts = inner("GO(") {
        guard let target = parts.first else { throw SpecError("\(at): GO() needs a target") }
        return .go(target: target, effects: Array(parts.dropFirst()))
    }
    if let parts = inner("EMIT(") { return .emit(effects: parts) }
    if let parts = inner("DELEGATE(") {
        guard let child = parts.first else { throw SpecError("\(at): DELEGATE() needs a child") }
        return .delegate(child: child)
    }
    throw SpecError(
        "\(at): unknown cell `\(t)`; expected IGNORE, HANDLE, UNREACHABLE, "
            + "GO(..), EMIT(..), DELEGATE(..)"
    )
}

/// Parse a `.tbl` fixture.
public func parseSpec(_ src: String, _ origin: String) throws -> Spec {
    var machine: String?
    var initial: String?
    var states: [String] = []
    var actions: [String] = []
    var cells: [[CellSpec]] = []

    for (n, raw) in src.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let line = strip(raw)
        if line.isEmpty { continue }
        let at = "\(origin):\(n + 1)"
        let w = words(line)

        switch w[0] {
        case "machine": machine = w[1]
        case "initial": initial = w[1]
        case "states": states = Array(w.dropFirst())
        case "actions": actions = Array(w.dropFirst())
        default:
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            let row = trim(String(parts[0]))
            let expected = cells.count < states.count ? states[cells.count] : ""
            guard row == expected else {
                throw SpecError(
                    "\(at): row \(cells.count) is `\(row)` but `states` says `\(expected)`; "
                        + "row order must match state order"
                )
            }
            var r: [CellSpec] = []
            for (j, p) in parts.dropFirst().enumerated() {
                r.append(try parseCell(String(p), "\(at) col \(j)"))
            }
            guard r.count == actions.count else {
                throw SpecError(
                    "\(at): row `\(row)` has \(r.count) cells, expected \(actions.count) "
                        + "(\(actions.joined(separator: " ")))"
                )
            }
            cells.append(r)
        }
    }

    guard let m = machine else { throw SpecError("\(origin): no `machine` line") }
    guard let i = initial else { throw SpecError("\(origin): no `initial` line") }
    return Spec(machine: m, initial: i, states: states, actions: actions, cells: cells)
}

private func parseKV(_ w: [String], _ at: String) throws -> [String: Int] {
    var m: [String: Int] = [:]
    for item in w {
        let parts = item.split(separator: "=", maxSplits: 1)
        guard parts.count == 2, let v = Int(parts[1]) else {
            throw SpecError("\(at): `\(item)` is not key=value with an integer")
        }
        m[String(parts[0])] = v
    }
    return m
}

/// Parse a `.trace` file, which may hold several traces.
public func parseTraces(_ src: String, _ origin: String) throws -> [Trace] {
    var out: [Trace] = []

    for (n, raw) in src.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let line = strip(raw)
        if line.isEmpty { continue }
        let at = "\(origin):\(n + 1)"
        let w = words(line)

        if w[0] == "trace" {
            out.append(Trace(name: w.count > 1 ? w[1] : "unnamed"))
            continue
        }
        guard !out.isEmpty else { throw SpecError("\(at): content before any `trace` line") }

        switch w[0] {
        case "ctx":
            out[out.count - 1].ctx = try parseKV(Array(w.dropFirst()), at)
        case "from":
            out[out.count - 1].from = w[1]
            out[out.count - 1].fromFields = try parseKV(Array(w.dropFirst(2)), at)
        default:
            guard let (lhs, rhs) = splitOnArrow(line) else {
                throw SpecError("\(at): step needs `=>`")
            }
            let lw = words(lhs)

            let bangParts = rhs.split(separator: "!", maxSplits: 1, omittingEmptySubsequences: false)
            let outcome = trim(String(bangParts[0]))
            let effects = bangParts.count > 1 ? words(String(bangParts[1])) : []

            let ow = words(outcome)
            let expect: Expect
            switch ow.first {
            case "stay": expect = .stay
            case "ignored": expect = .ignored
            case "go":
                guard ow.count > 1 else { throw SpecError("\(at): `go` needs a state") }
                expect = .go(state: ow[1], fields: try parseKV(Array(ow.dropFirst(2)), at))
            default:
                throw SpecError("\(at): expected `go <State>`, `stay`, or `ignored`")
            }
            out[out.count - 1].steps.append(
                TraceStep(
                    action: lw[0],
                    args: try parseKV(Array(lw.dropFirst()), at),
                    expect: expect,
                    effects: effects
                )
            )
        }
    }
    return out
}

private func matches(_ got: Cell, _ want: CellSpec) -> Bool {
    func norm(_ v: [String]) -> [String] { v.map(lastSegment) }
    switch (got, want) {
    case (.ignore, .ignore), (.handle, .handle), (.unreachable, .unreachable):
        return true
    case let (.go(gt, ge), .go(wt, we)):
        return lastSegment(gt) == lastSegment(wt) && norm(ge) == norm(we)
    case let (.emit(ge), .emit(we)):
        return norm(ge) == norm(we)
    case let (.delegate(gc), .delegate(wc)):
        return lastSegment(gc) == lastSegment(wc)
    default:
        return false
    }
}

/// Compare a generated table against a fixture, cell by cell.
///
/// Not redundant with trace replay: several wrong tables produce right answers
/// on any one trace.
public func checkTable(_ got: Table, _ want: Spec) -> [String] {
    var errs: [String] = []
    if got.machine != want.machine {
        errs.append("machine name: got `\(got.machine)`, want `\(want.machine)`")
    }
    if got.initial != want.initial {
        errs.append("initial: got \(String(describing: got.initial)), want `\(want.initial)`")
    }
    if got.states != want.states {
        errs.append("states: got \(got.states), want \(want.states)")
        return errs
    }
    if got.actions != want.actions {
        errs.append("actions: got \(got.actions), want \(want.actions)")
        return errs
    }
    for (i, row) in want.cells.enumerated() {
        for (j, spec) in row.enumerated() {
            let cell = got.cell(i, j)
            if !matches(cell, spec) {
                errs.append(
                    "cell (\(want.states[i]), \(want.actions[j])): got \(cell), want \(spec.text)"
                )
            }
        }
    }
    return errs
}
