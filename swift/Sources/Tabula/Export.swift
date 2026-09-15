/// Diagram and grid rendering.
///
/// Pure functions of `Table`, which is the payoff for emitting the matrix as
/// data: none of this had to be built as a feature.
public enum Export {

    /// The matrix as an aligned ASCII grid.
    ///
    /// Lines are right-trimmed: trailing padding is invisible, trips every
    /// whitespace check, and makes golden snapshots noisy in review.
    ///
    /// Must match the Rust and Kotlin renderers byte for byte — the golden
    /// `.grid` files in `spec/conformance` are shared, and two renderers
    /// agreeing on padding is a stronger statement than it looks.
    public static func toGrid(_ t: Table) -> String {
        func text(_ c: Cell) -> String {
            switch c {
            case .ignore: return "IGNORE"
            case let .go(target, effects):
                return effects.isEmpty
                    ? "GO(\(target))"
                    : "GO(\(target), \(effects.joined(separator: "+")))"
            case let .emit(effects): return "EMIT(\(effects.joined(separator: "+")))"
            case .handle: return "HANDLE"
            case let .delegate(child): return "DELEGATE(\(child))"
            case .unreachable: return "UNREACHABLE"
            }
        }

        let texts = t.cells.map { $0.map(text) }
        let labelWidth = (t.states.map(\.count) + [t.machine.count]).max() ?? 0
        let colWidth = t.actions.indices.map { j in
            (texts.map { $0[j].count } + [t.actions[j].count]).max() ?? 0
        }

        func pad(_ s: String, _ w: Int) -> String {
            s + String(repeating: " ", count: max(0, w - s.count))
        }

        func line(_ head: String, _ cells: [String]) -> String {
            var l = pad(head, labelWidth)
            for (j, c) in cells.enumerated() { l += "  " + pad(c, colWidth[j]) }
            while l.hasSuffix(" ") { l.removeLast() }
            return l + "\n"
        }

        var out = line(t.machine, t.actions)
        for (i, s) in t.states.enumerated() { out += line(s, texts[i]) }
        return out
    }

    /// Mermaid `stateDiagram-v2`.
    ///
    /// Only statically-known transitions become real edges. `handle` and
    /// `delegate` cells are drawn as annotated self-loops, because their target
    /// is not knowable at build time and a diagram that pretends otherwise lies.
    public static func toMermaid(_ t: Table) -> String {
        var out = "stateDiagram-v2\n"
        if let initial = t.initial { out += "    [*] --> \(initial)\n" }
        for e in edges(t) { out += "    \(e.from) --> \(e.to): \(e.label)\n" }
        return out
    }

    /// Graphviz DOT. Dynamic edges are dashed; static ones are solid.
    public static func toDot(_ t: Table) -> String {
        var out = "digraph \(t.machine) {\n    rankdir=LR;\n"
        out += "    node [shape=box, style=rounded];\n"
        if let initial = t.initial {
            out += "    __start [shape=point];\n"
            out += "    __start -> \(initial);\n"
        }
        for e in edges(t) {
            let style = e.isStatic ? "" : ", style=dashed"
            out += "    \(e.from) -> \(e.to) [label=\"\(e.label)\"\(style)];\n"
        }
        out += "}\n"
        return out
    }

    /// The build-time coverage report.
    ///
    /// Thresholds are the lint's, referenced rather than repeated: this and
    /// `report` are two views of one matrix and must not disagree about what
    /// is worth warning about.
    public static func toCoverageReport(_ t: Table) -> String {
        let c = t.coverage()
        var out = "\(t.machine): \(c.total) cells "
        out += "(\(t.states.count)x\(t.actions.count)), \(c.requiredMembers) required members\n"
        out += "  ignore \(c.ignore) | go \(c.go) | emit \(c.emit) | "
        out += "handle \(c.handle) | delegate \(c.delegate) | unreachable \(c.unreachable)\n"
        if c.ignorePercent >= ignoreHeavyPercent {
            out += "  warning: \(c.ignorePercent)% of cells are IGNORE; "
            out += "consider splitting this machine\n"
        }
        // One or two deliberate `unreachable` cells stay silent. See spec/cells.md.
        if c.unreachablePercent >= unreachableHeavyPercent {
            out += "  warning: \(c.unreachable) UNREACHABLE cell(s); usually a modelling error\n"
        }
        // With any dynamic cell present, staticallyUnreached is an
        // approximation, so the report must not present it as a result.
        if t.isFullyStatic() {
            for state in t.staticallyUnreached() {
                out += "  warning: `\(state)` has no static incoming transition\n"
            }
        }
        return out
    }

    /// One drawable edge. `isStatic` is false when the target is not knowable.
    private struct Edge {
        let from: String
        let to: String
        let label: String
        let isStatic: Bool
    }

    private static func label(_ action: String, _ effects: [String]) -> String {
        effects.isEmpty ? action : "\(action) / \(effects.joined(separator: ", "))"
    }

    /// Every drawable edge, in row-major matrix order.
    ///
    /// One walk feeding all three formats, so a machine renders in the same
    /// order whichever you ask for. Row-major because that is the order the
    /// matrix is read in — and because Rust rendered mermaid in two passes for
    /// a while, every `go` edge before every self-loop, which produced the same
    /// edge set in a different order from this. Nothing compared diagram
    /// output, so nothing said so.
    ///
    /// `ignore` and `unreachable` draw nothing. Neither is a transition: one
    /// says the action does not apply, the other says the pair cannot occur.
    private static func edges(_ t: Table) -> [Edge] {
        var out: [Edge] = []
        for (i, row) in t.cells.enumerated() {
            let from = t.states[i]
            for (j, cell) in row.enumerated() {
                let action = t.actions[j]
                switch cell {
                case let .go(target, effects):
                    out.append(Edge(from: from, to: target,
                                    label: label(action, effects), isStatic: true))
                case let .emit(effects):
                    out.append(Edge(from: from, to: from,
                                    label: label(action, effects), isStatic: true))
                case .handle:
                    out.append(Edge(from: from, to: from,
                                    label: "\(action) / ?handle", isStatic: false))
                case let .delegate(child):
                    out.append(Edge(from: from, to: from,
                                    label: "\(action) / >\(child)", isStatic: false))
                case .ignore, .unreachable:
                    break
                }
            }
        }
        return out
    }
}
