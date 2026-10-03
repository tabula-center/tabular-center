// Rendering a `TABLE`: the aligned grid, Mermaid and DOT diagrams, and the
// build-time coverage report -- all from one walk over the matrix, so every
// format lists a machine in the same order.
package center.tabula

/**
 * Diagram and grid rendering.
 *
 * Pure functions of [Table], which is the payoff for emitting the matrix as
 * data: none of this had to be built as a feature.
 *
 * - `toGrid`: The matrix as an aligned ASCII grid.
 * - `toMermaid`: Mermaid `stateDiagram-v2`.
 * - `toDot`: Graphviz DOT.
 * - `toCoverageReport`: The build-time coverage report.
 * - `edges`: Every drawable edge, in row-major matrix order.
 */
object Export {

    fun toGrid(t: Table): String {
        fun text(c: Cell): String = when (c) {
            is Cell.Ignore -> "IGNORE"
            is Cell.Go -> if (c.effects.isEmpty()) "GO(${c.target})"
                          else "GO(${c.target}, ${c.effects.joinToString("+")})"
            is Cell.Emit -> "EMIT(${c.effects.joinToString("+")})"
            is Cell.Handle -> "HANDLE"
            is Cell.Delegate -> "DELEGATE(${c.child})"
            is Cell.Unreachable -> "UNREACHABLE"
        }

        val texts = t.cells.map { row -> row.map(::text) }
        val labelW = (t.states.map { it.length } + t.machine.length).max()
        val colW = t.actions.indices.map { j ->
            (texts.map { it[j].length } + t.actions[j].length).max()
        }

        val sb = StringBuilder()
        fun line(head: String, cells: List<String>) {
            val l = StringBuilder(head.padEnd(labelW))
            cells.forEachIndexed { j, c -> l.append("  ").append(c.padEnd(colW[j])) }
            sb.append(l.toString().trimEnd()).append('\n')
        }
        line(t.machine, t.actions)
        t.states.forEachIndexed { i, s -> line(s, texts[i]) }
        return sb.toString()
    }

    fun toMermaid(t: Table): String {
        val sb = StringBuilder("stateDiagram-v2\n")
        t.initial?.let { sb.append("    [*] --> $it\n") }
        for (e in edges(t)) sb.append("    ${e.from} --> ${e.to}: ${e.label}\n")
        return sb.toString()
    }

    fun toDot(t: Table): String {
        val sb = StringBuilder("digraph ${t.machine} {\n    rankdir=LR;\n")
        sb.append("    node [shape=box, style=rounded];\n")
        t.initial?.let {
            sb.append("    __start [shape=point];\n")
            sb.append("    __start -> $it;\n")
        }
        for (e in edges(t)) {
            val style = if (e.isStatic) "" else ", style=dashed"
            sb.append("    ${e.from} -> ${e.to} [label=\"${e.label}\"$style];\n")
        }
        sb.append("}\n")
        return sb.toString()
    }

    fun toCoverageReport(t: Table): String {
        val c = t.coverage()
        val sb = StringBuilder(
            "${t.machine}: ${c.total} cells (${t.states.size}x${t.actions.size}), " +
                "${c.requiredMembers} required members\n",
        )
        sb.append(
            "  ignore ${c.ignore} | go ${c.go} | emit ${c.emit} | " +
                "handle ${c.handle} | delegate ${c.delegate} | unreachable ${c.unreachable}\n",
        )
        if (c.ignorePercent >= IGNORE_HEAVY_PERCENT) {
            sb.append(
                "  warning: ${c.ignorePercent}% of cells are IGNORE; " +
                    "consider splitting this machine\n",
            )
        }
        if (c.unreachablePercent >= UNREACHABLE_HEAVY_PERCENT) {
            sb.append("  warning: ${c.unreachable} UNREACHABLE cell(s); usually a modelling error\n")
        }
        if (t.isFullyStatic()) {
            for (state in t.staticallyUnreached()) {
                sb.append("  warning: `$state` has no static incoming transition\n")
            }
        }
        return sb.toString()
    }

    /** One drawable edge. [isStatic] is false when the target is not knowable. */
    private data class Edge(
        val from: String,
        val to: String,
        val label: String,
        val isStatic: Boolean,
    )

    private fun label(action: String, effects: List<String>): String =
        if (effects.isEmpty()) action else "$action / ${effects.joinToString(", ")}"

    private fun edges(t: Table): List<Edge> {
        val out = mutableListOf<Edge>()
        t.cells.forEachIndexed { i, row ->
            val from = t.states[i]
            row.forEachIndexed { j, cell ->
                val action = t.actions[j]
                when (cell) {
                    is Cell.Go ->
                        out.add(Edge(from, cell.target, label(action, cell.effects), true))
                    is Cell.Emit -> out.add(Edge(from, from, label(action, cell.effects), true))
                    is Cell.Handle -> out.add(Edge(from, from, "$action / ?handle", false))
                    is Cell.Delegate -> out.add(Edge(from, from, "$action / >${cell.child}", false))
                    is Cell.Ignore, is Cell.Unreachable -> {}
                }
            }
        }
        return out
    }
}
