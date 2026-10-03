/// Diagram and grid rendering.
///
/// Pure functions of `Table`, which is the payoff for emitting the matrix as
/// data: none of this had to be built as a feature.
///
/// - `toGrid`: The matrix as an aligned ASCII grid.
/// - `toMermaid`: Mermaid `stateDiagram-v2`.
/// - `toDot`: Graphviz DOT.
/// - `toCoverageReport`: The build-time coverage report.
/// - `edges`: Every drawable edge, in row-major matrix order.
public enum Export {

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

    public static func toMermaid(_ t: Table) -> String {
        var out = "stateDiagram-v2\n"
        if let initial = t.initial { out += "    [*] --> \(initial)\n" }
        for e in edges(t) { out += "    \(e.from) --> \(e.to): \(e.label)\n" }
        return out
    }

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
        if c.unreachablePercent >= unreachableHeavyPercent {
            out += "  warning: \(c.unreachable) UNREACHABLE cell(s); usually a modelling error\n"
        }
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
