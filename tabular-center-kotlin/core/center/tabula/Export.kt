package center.tabula

/**
 * Diagram and grid rendering.
 *
 * Pure functions of [Table], which is the payoff for emitting the matrix as
 * data: none of this had to be built as a feature.
 */
object Export {

    /**
     * The matrix as an aligned ASCII grid.
     *
     * Lines are right-trimmed: trailing padding is invisible, trips every
     * whitespace check, and makes golden snapshots noisy in review. Alignment
     * only needs the padding *between* columns.
     *
     * Must match the Rust renderer byte for byte — the golden `.grid` files in
     * `spec/conformance` are shared.
     */
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

    /**
     * Mermaid `stateDiagram-v2`.
     *
     * Only statically-known transitions become real edges. `HANDLE` and
     * `DELEGATE` cells are drawn as annotated self-loops, because their target
     * is not knowable at build time and a diagram that pretends otherwise lies.
     */
    fun toMermaid(t: Table): String {
        val sb = StringBuilder("stateDiagram-v2\n")
        t.initial?.let { sb.append("    [*] --> $it\n") }
        for (e in edges(t)) sb.append("    ${e.from} --> ${e.to}: ${e.label}\n")
        return sb.toString()
    }

    /** Graphviz DOT. Dynamic edges are dashed; static ones are solid. */
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

    /**
     * The build-time coverage report.
     *
     * Thresholds are the lint's, imported rather than repeated: this and
     * [report] are two views of one matrix and must not disagree about what is
     * worth warning about.
     */
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
        // One or two deliberate UNREACHABLE cells stay silent. See spec/cells.md.
        if (c.unreachablePercent >= UNREACHABLE_HEAVY_PERCENT) {
            sb.append("  warning: ${c.unreachable} UNREACHABLE cell(s); usually a modelling error\n")
        }
        // With any dynamic cell present, staticallyUnreached is an
        // approximation, so the report must not present it as a result.
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

    /**
     * Every drawable edge, in row-major matrix order.
     *
     * One walk feeding all three formats, so a machine renders in the same
     * order whichever you ask for. Row-major because that is the order the
     * matrix is read in — and because Rust rendered mermaid in two passes for
     * a while, every `GO` edge before every self-loop, which produced the same
     * edge set in a different order from this. Nothing compared diagram
     * output, so nothing said so.
     *
     * `IGNORE` and `UNREACHABLE` draw nothing. Neither is a transition: one
     * says the action does not apply, the other says the pair cannot occur.
     */
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
