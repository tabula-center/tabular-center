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
    /// Only statically-known transitions become edges. `handle` and `delegate`
    /// cells are drawn as annotated self-loops, because their target is not
    /// knowable at build time and a diagram that pretends otherwise lies.
    public static func toMermaid(_ t: Table) -> String {
        func label(_ action: String, _ effects: [String]) -> String {
            effects.isEmpty ? action : "\(action) / \(effects.joined(separator: ", "))"
        }

        var out = "stateDiagram-v2\n"
        if let initial = t.initial { out += "    [*] --> \(initial)\n" }

        for (i, row) in t.cells.enumerated() {
            let from = t.states[i]
            for (j, cell) in row.enumerated() {
                switch cell {
                case let .go(target, effects):
                    out += "    \(from) --> \(target): \(label(t.actions[j], effects))\n"
                case let .emit(effects):
                    out += "    \(from) --> \(from): \(label(t.actions[j], effects))\n"
                case .handle:
                    out += "    \(from) --> \(from): \(t.actions[j]) / ?handle\n"
                case let .delegate(child):
                    out += "    \(from) --> \(from): \(t.actions[j]) / >\(child)\n"
                default:
                    break
                }
            }
        }
        return out
    }
}
