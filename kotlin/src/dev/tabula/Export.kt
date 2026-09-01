package dev.tabula

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
     * Only statically-known transitions become edges. `HANDLE` and `DELEGATE`
     * cells are drawn as annotated self-loops, because their target is not
     * knowable at build time and a diagram that pretends otherwise lies.
     */
    fun toMermaid(t: Table): String {
        val sb = StringBuilder("stateDiagram-v2\n")
        t.initial?.let { sb.append("    [*] --> $it\n") }
        fun label(action: String, effects: List<String>) =
            if (effects.isEmpty()) action else "$action / ${effects.joinToString(", ")}"

        t.cells.forEachIndexed { i, row ->
            row.forEachIndexed { j, cell ->
                val from = t.states[i]
                when (cell) {
                    is Cell.Go -> sb.append("    $from --> ${cell.target}: ${label(t.actions[j], cell.effects)}\n")
                    is Cell.Emit -> sb.append("    $from --> $from: ${label(t.actions[j], cell.effects)}\n")
                    is Cell.Handle -> sb.append("    $from --> $from: ${t.actions[j]} / ?handle\n")
                    is Cell.Delegate -> sb.append("    $from --> $from: ${t.actions[j]} / >${cell.child}\n")
                    else -> {}
                }
            }
        }
        return sb.toString()
    }
}
