package conformance

import dev.tabula.*

/**
 * Parses `spec/conformance` — the same `.tbl` and `.trace` files the Rust
 * harness reads.
 *
 * A port, deliberately: the format was chosen to parse in about sixty lines
 * precisely so each language could own its parser without a dependency. Two
 * small parsers that agree are worth more than one shared one that neither
 * language can build offline.
 */

/** A cell as the fixture declares it. */
sealed interface CellSpecFixture {
    data object Ignore : CellSpecFixture
    data object Handle : CellSpecFixture
    data object Unreachable : CellSpecFixture
    data class Go(val target: String, val effects: List<String>) : CellSpecFixture
    data class Emit(val effects: List<String>) : CellSpecFixture
    data class Delegate(val child: String) : CellSpecFixture

    override fun toString(): String
}

private fun cellText(c: CellSpecFixture): String = when (c) {
    is CellSpecFixture.Ignore -> "IGNORE"
    is CellSpecFixture.Handle -> "HANDLE"
    is CellSpecFixture.Unreachable -> "UNREACHABLE"
    is CellSpecFixture.Go ->
        if (c.effects.isEmpty()) "GO(${c.target})" else "GO(${c.target}, ${c.effects.joinToString(", ")})"
    is CellSpecFixture.Emit -> "EMIT(${c.effects.joinToString(", ")})"
    is CellSpecFixture.Delegate -> "DELEGATE(${c.child})"
}

/** A parsed `.tbl` fixture. */
data class Spec(
    val machine: String,
    val initial: String,
    val states: List<String>,
    val actions: List<String>,
    val cells: List<List<CellSpecFixture>>,
)

/** What a trace step expects. */
sealed interface Expect {
    data class Go(val state: String, val fields: Map<String, Long>) : Expect
    data object Stay : Expect
    data object Ignored : Expect
}

/** One line of a trace. */
data class TraceStep(
    val action: String,
    val args: Map<String, Long>,
    val expect: Expect,
    val effects: List<String>,
)

/** A parsed `.trace` block. */
data class Trace(
    val name: String,
    val ctx: Map<String, Long>,
    val from: String,
    val fromFields: Map<String, Long>,
    val steps: List<TraceStep>,
)

/**
 * Reduce an effect or state rendering to its bare variant name.
 *
 * Three shapes must all land on `StopClock`: the fixture's own `StopClock`, a
 * qualified `F.StopClock`, and Kotlin's `toString` on a data class,
 * `StopClock(reason=1)`.
 *
 * **Order matters.** Taking the last path segment first breaks on the third,
 * because `(reason=1)` may contain a separator. Strip the payload, then split
 * the path. The Rust harness learned this the same way — four conformance
 * failures — and the two must agree.
 */
fun lastSegment(s: String): String {
    val cut = s.indexOfFirst { it == '(' || it == '{' || it == ' ' }
    val head = if (cut >= 0) s.substring(0, cut) else s
    return head.substringAfterLast('.').substringAfterLast(':').trim()
}

private fun strip(line: String): String {
    val i = line.indexOf('#')
    return (if (i >= 0) line.substring(0, i) else line).trim()
}

private fun parseCell(text: String, at: String): CellSpecFixture {
    val t = text.trim()
    fun split(inner: String) = inner.split(',').map { it.trim() }.filter { it.isNotEmpty() }
    return when {
        t == "IGNORE" -> CellSpecFixture.Ignore
        t == "HANDLE" -> CellSpecFixture.Handle
        t == "UNREACHABLE" -> CellSpecFixture.Unreachable
        t.startsWith("GO(") && t.endsWith(")") -> {
            val parts = split(t.removePrefix("GO(").removeSuffix(")"))
            require(parts.isNotEmpty()) { "$at: GO() needs a target" }
            CellSpecFixture.Go(parts.first(), parts.drop(1))
        }
        t.startsWith("EMIT(") && t.endsWith(")") ->
            CellSpecFixture.Emit(split(t.removePrefix("EMIT(").removeSuffix(")")))
        t.startsWith("DELEGATE(") && t.endsWith(")") ->
            CellSpecFixture.Delegate(t.removePrefix("DELEGATE(").removeSuffix(")").trim())
        else -> error(
            "$at: unknown cell `$t`; expected IGNORE, HANDLE, UNREACHABLE, " +
                "GO(..), EMIT(..), DELEGATE(..)"
        )
    }
}

/** Parse a `.tbl` fixture. */
fun parseSpec(src: String, origin: String): Spec {
    var machine: String? = null
    var initial: String? = null
    var states = emptyList<String>()
    var actions = emptyList<String>()
    val cells = mutableListOf<List<CellSpecFixture>>()

    src.lines().forEachIndexed { n, raw ->
        val line = strip(raw)
        if (line.isEmpty()) return@forEachIndexed
        val at = "$origin:${n + 1}"
        val words = line.split(Regex("\\s+"))
        when (words[0]) {
            "machine" -> machine = words[1]
            "initial" -> initial = words[1]
            "states" -> states = words.drop(1)
            "actions" -> actions = words.drop(1)
            else -> {
                val parts = line.split('|')
                val row = parts.first().trim()
                val expected = states.getOrNull(cells.size) ?: ""
                require(row == expected) {
                    "$at: row ${cells.size} is `$row` but `states` says `$expected`; " +
                        "row order must match state order"
                }
                val r = parts.drop(1).mapIndexed { j, p -> parseCell(p, "$at col $j") }
                require(r.size == actions.size) {
                    "$at: row `$row` has ${r.size} cells, expected ${actions.size} " +
                        "(${actions.joinToString(" ")})"
                }
                cells.add(r)
            }
        }
    }
    return Spec(
        machine = requireNotNull(machine) { "$origin: no `machine` line" },
        initial = requireNotNull(initial) { "$origin: no `initial` line" },
        states = states,
        actions = actions,
        cells = cells,
    )
}

private fun parseKv(words: List<String>, at: String): Map<String, Long> =
    words.associate { w ->
        val (k, v) = w.split('=', limit = 2).also {
            require(it.size == 2) { "$at: `$w` is not key=value" }
        }
        k to (v.toLongOrNull() ?: error("$at: `$v` is not an integer"))
    }

/** Parse a `.trace` file, which may hold several traces. */
fun parseTraces(src: String, origin: String): List<Trace> {
    val out = mutableListOf<Trace>()
    src.lines().forEachIndexed { n, raw ->
        val line = strip(raw)
        if (line.isEmpty()) return@forEachIndexed
        val at = "$origin:${n + 1}"
        val words = line.split(Regex("\\s+"))

        if (words[0] == "trace") {
            out.add(Trace(words.getOrElse(1) { "unnamed" }, emptyMap(), "", emptyMap(), emptyList()))
            return@forEachIndexed
        }
        require(out.isNotEmpty()) { "$at: content before any `trace` line" }
        val t = out.removeLast()

        out.add(
            when (words[0]) {
                "ctx" -> t.copy(ctx = parseKv(words.drop(1), at))
                // `from` accepts payload fields exactly as `go` does. It did
                // not, once, and silently started a composition trace in the
                // wrong child state.
                "from" -> t.copy(from = words[1], fromFields = parseKv(words.drop(2), at))
                else -> {
                    val (lhs, rhs) = line.split("=>", limit = 2).also {
                        require(it.size == 2) { "$at: step needs `=>`" }
                    }
                    val lw = lhs.trim().split(Regex("\\s+"))
                    val bang = rhs.indexOf('!')
                    val outcome = (if (bang >= 0) rhs.substring(0, bang) else rhs).trim()
                    val effects =
                        if (bang >= 0) rhs.substring(bang + 1).trim().split(Regex("\\s+"))
                            .filter { it.isNotEmpty() }
                        else emptyList()
                    val ow = outcome.split(Regex("\\s+"))
                    val expect = when (ow.firstOrNull()) {
                        "stay" -> Expect.Stay
                        "ignored" -> Expect.Ignored
                        "go" -> Expect.Go(
                            ow.getOrElse(1) { error("$at: `go` needs a state") },
                            parseKv(ow.drop(2), at),
                        )
                        else -> error("$at: expected `go <State>`, `stay`, or `ignored`")
                    }
                    t.copy(
                        steps = t.steps + TraceStep(lw[0], parseKv(lw.drop(1), at), expect, effects),
                    )
                }
            }
        )
    }
    return out
}

private fun cellMatches(got: Cell, want: CellSpecFixture): Boolean {
    fun norm(v: List<String>) = v.map(::lastSegment)
    return when {
        got is Cell.Ignore && want is CellSpecFixture.Ignore -> true
        got is Cell.Handle && want is CellSpecFixture.Handle -> true
        got is Cell.Unreachable && want is CellSpecFixture.Unreachable -> true
        got is Cell.Go && want is CellSpecFixture.Go ->
            lastSegment(got.target) == lastSegment(want.target) &&
                norm(got.effects) == norm(want.effects)
        got is Cell.Emit && want is CellSpecFixture.Emit -> norm(got.effects) == norm(want.effects)
        got is Cell.Delegate && want is CellSpecFixture.Delegate ->
            lastSegment(got.child) == lastSegment(want.child)
        else -> false
    }
}

/**
 * Compare a generated table against a fixture, cell by cell.
 *
 * Not redundant with trace replay: several wrong tables produce right answers
 * on any one trace.
 */
fun checkTable(got: Table, want: Spec): List<String> {
    val errs = mutableListOf<String>()
    if (got.machine != want.machine) errs.add("machine name: got `${got.machine}`, want `${want.machine}`")
    if (got.initial != want.initial) errs.add("initial: got ${got.initial}, want `${want.initial}`")
    if (got.states != want.states) {
        errs.add("states: got ${got.states}, want ${want.states}")
        return errs
    }
    if (got.actions != want.actions) {
        errs.add("actions: got ${got.actions}, want ${want.actions}")
        return errs
    }
    want.cells.forEachIndexed { i, row ->
        row.forEachIndexed { j, spec ->
            val c = got.cell(i, j)
            if (!cellMatches(c, spec)) {
                errs.add("cell (${want.states[i]}, ${want.actions[j]}): got $c, want ${cellText(spec)}")
            }
        }
    }
    return errs
}
