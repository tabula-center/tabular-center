package dev.tabula

/**
 * Findings computable from a machine's table.
 *
 * Everything here is a **warning**, never an error. Each rule is a judgement
 * call with legitimate exceptions, and a lint that fails a build on a
 * judgement call teaches people to disable lints.
 *
 * Two rules govern the set, learned while writing the Rust version:
 *
 * - A lint that fires on healthy machines is a lint people turn off.
 *   [NoStaticEntry] reports only for a fully static matrix; [UnreachableHeavy]
 *   fires on a concentration, not on the one or two deliberate assertions the
 *   cell kind exists for.
 * - Two warnings for one problem is noise. [DeadRow] subsumes [NoStaticExit].
 */
sealed interface Finding {
    /** Stable diagnostic code, matching `spec/diagnostics.md`. */
    val code: String

    /** Human-readable message, remedy included. */
    val message: String

    /** Nothing can transition into this state, in a fully static matrix. */
    data class NoStaticEntry(val state: String) : Finding {
        override val code = "tabula::no-static-entry"
        override val message =
            "nothing can transition into `$state`; " +
                "every cell in this matrix is static, so it is genuinely unreachable"
    }

    /** No cell in this row can statically leave it. */
    data class NoStaticExit(val state: String) : Finding {
        override val code = "tabula::no-static-exit"
        override val message =
            "no cell in row `$state` can leave it statically; " +
                "confirm this state is meant to be terminal"
    }

    /** Every cell in this row ignores. */
    data class DeadRow(val state: String) : Finding {
        override val code = "tabula::dead-row"
        override val message =
            "every cell in row `$state` ignores; confirm this state is meant to be terminal"
    }

    /** No state responds to this action. */
    data class DeadColumn(val action: String) : Finding {
        override val code = "tabula::dead-column"
        override val message =
            "no state responds to `$action`; the action is dead or a row was missed"
    }

    /** The matrix is overwhelmingly `IGNORE`. */
    data class IgnoreHeavy(val percent: Int) : Finding {
        override val code = "tabula::ignore-heavy"
        override val message =
            "$percent% of cells are IGNORE; consider splitting this machine"
    }

    /** `UNREACHABLE` occupies a large share of the matrix. */
    data class UnreachableHeavy(val count: Int, val percent: Int) : Finding {
        override val code = "tabula::unreachable-heavy"
        override val message =
            "$count UNREACHABLE cells ($percent% of the matrix); " +
                "a concentration this high usually means the alphabet is wrong"
    }
}

/** Percentage of `IGNORE` cells above which [Finding.IgnoreHeavy] fires. */
const val IGNORE_HEAVY_PERCENT = 70

/** Percentage of `UNREACHABLE` cells above which [Finding.UnreachableHeavy] fires. */
const val UNREACHABLE_HEAVY_PERCENT = 25

/** Every finding for a machine, in a stable order. */
fun lint(t: Table): List<Finding> = buildList {
    // Only meaningful when every cell is static; otherwise a HANDLE cell could
    // reach anything and the rule would be guessing.
    if (t.isFullyStatic()) {
        t.staticallyUnreached().forEach { add(Finding.NoStaticEntry(it)) }
    }

    t.cells.forEachIndexed { i, row ->
        if (row.all { it is Cell.Ignore }) {
            add(Finding.DeadRow(t.states[i]))
            return@forEachIndexed
        }
        if (row.none { it.staticTarget != null || !it.isStatic }) {
            add(Finding.NoStaticExit(t.states[i]))
        }
    }

    t.actions.forEachIndexed { j, action ->
        if (t.cells.all { it[j] is Cell.Ignore }) add(Finding.DeadColumn(action))
    }

    val c = t.coverage()
    if (c.ignorePercent >= IGNORE_HEAVY_PERCENT) add(Finding.IgnoreHeavy(c.ignorePercent))
    if (c.unreachablePercent >= UNREACHABLE_HEAVY_PERCENT) {
        add(Finding.UnreachableHeavy(c.unreachable, c.unreachablePercent))
    }
}

/** Findings rendered one per line, prefixed with the machine name. */
fun report(t: Table): String =
    lint(t).joinToString("") { "warning[${it.code}]: ${t.machine}: ${it.message}\n" }
