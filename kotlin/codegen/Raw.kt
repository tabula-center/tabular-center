package codegen

/**
 * The flat, stringly-typed shape a KSP processor can fill in without judgement.
 *
 * ## Why this layer exists
 *
 * The KSP processor is the one piece that needs Maven, so it is the one piece
 * that cannot be tested here. The remedy is to make it as small and as dumb as
 * possible: reading `KSAnnotation` arguments into strings is mechanical and
 * reviewable by eye, while *validating* those strings is where the real
 * decisions and the real diagnostics live.
 *
 * So the processor produces a [RawMachine] and calls [buildDesc]. Everything
 * below runs and is tested without KSP.
 */
/**
 * A happy path: a named route through the matrix, from a state to a state.
 *
 * Named because a machine may have more than one, and the narrowed calling
 * surface has to say which it narrows to.
 */
data class RawPath(val name: String, val elements: List<String>) {
    /** States, at the even positions. */
    val states: List<String> get() = elements.filterIndexed { i, _ -> i % 2 == 0 }

    /** Actions, at the odd positions -- one per hop. */
    val actions: List<String> get() = elements.filterIndexed { i, _ -> i % 2 == 1 }

    /** Hops, as `(from, action, to)`. Empty when the shape is wrong. */
    val hops: List<Triple<String, String, String>>
        get() = if (elements.size < 3 || elements.size % 2 == 0) emptyList()
        else (0 until elements.size / 2).map {
            Triple(elements[it * 2], elements[it * 2 + 1], elements[it * 2 + 2])
        }
}

data class RawMachine(
    val packageName: String,
    val machine: String,
    val stateType: String,
    val actionType: String,
    val effectType: String,
    val ctxType: String,
    val initial: String,
    /** Declared state variants, in row order. */
    val states: List<RawVariant>,
    val actions: List<RawVariant>,
    val effects: List<RawVariant>,
    val rows: List<RawRow>,
    val prototypeModifiers: List<String> = emptyList(),
    val children: List<ChildDesc> = emptyList(),
    /**
     * Declared happy paths, in declaration order. See `spec/happy-paths.md`.
     *
     * Defaulted to empty, which is the whole feature's constraint expressed as
     * a parameter: a machine without a spine is constructed exactly as before,
     * and every existing caller -- the KSP processor, `MachineSyntax`, the
     * hand-built descriptions in `Main.kt` -- compiles untouched.
     *
     * Read at generation time and discarded. Nothing here reaches `Table`, so
     * a machine with a spine and the same machine written longhand produce
     * byte-identical `TABLE`, `.grid`, `.lint`, `.cov` and `.mmd`.
     */
    val paths: List<RawPath> = emptyList(),
)

/** A variant as the processor reads it, before validation. */
data class RawVariant(
    val name: String,
    val hasPayload: Boolean = false,
    /** `name to type`, for `tabula::payload-hoist`. Optional. */
    val fields: List<Pair<String, String>> = emptyList(),
)

/** One `@Row`: the state it belongs to, then one cell per action. */
data class RawRow(val state: String, val cells: List<RawCell>)

/** One `@CellSpec`, before validation. */
data class RawCell(
    val kind: String,
    val target: String = "",
    /** Literal constructor arguments for [target], e.g. `"(0)"`. */
    val targetArgs: String = "",
    val effects: List<String> = emptyList(),
    val child: String = "",
)

/** A diagnostic, carrying the code from `spec/diagnostics.md`. */
class TabulaError(val code: String, override val message: String) : IllegalArgumentException(message)

private fun fail(code: String, message: String): Nothing = throw TabulaError(code, "$code: $message")

/**
 * Validate a [RawMachine] and turn it into a [MachineDesc].
 *
 * Every diagnostic in `spec/diagnostics.md` that concerns the *declaration*
 * fires here, which means each one has a test and none of them lives in the
 * untested processor.
 */
fun buildDesc(raw: RawMachine): MachineDesc {
    val stateNames = raw.states.map { it.name }
    val actionNames = raw.actions.map { it.name }
    val effectNames = raw.effects.map { it.name }
    val payloadStates = raw.states.filter { it.hasPayload }.map { it.name }.toSet()

    if (raw.initial !in stateNames) {
        fail(
            "tabula::unknown-state",
            "initial state `${raw.initial}` is not declared. States: ${stateNames.joinToString(" ")}"
        )
    }

    validatePaths(raw, stateNames, actionNames)

    // Rows must correspond to states one-to-one, in order. Position is how a
    // row is identified, so an out-of-order row is not a reordering -- it is a
    // row for the wrong state.
    raw.rows.forEachIndexed { i, row ->
        val expected = stateNames.getOrNull(i)
            ?: fail(
                "tabula::extra-row",
                "row `${row.state}` does not correspond to a declared state. " +
                    "States: ${stateNames.joinToString(" ")}"
            )
        if (row.state != expected) {
            fail(
                "tabula::missing-row",
                "row $i is `${row.state}` but `states` says `$expected`. " +
                    "Every state needs exactly one row, in declaration order. " +
                    "States: ${stateNames.joinToString(" ")}"
            )
        }
    }
    if (raw.rows.size < stateNames.size) {
        fail(
            "tabula::missing-row",
            "state `${stateNames[raw.rows.size]}` has no row. " +
                "Every state needs exactly one row, in declaration order. " +
                "States: ${stateNames.joinToString(" ")}"
        )
    }

    val rows = raw.rows.mapIndexed { i, row ->
        if (row.cells.size != actionNames.size) {
            fail(
                "tabula::row-arity",
                "row `${row.state}` has ${row.cells.size} cells, expected ${actionNames.size}. " +
                    "Expected columns: ${actionNames.joinToString(" ")}"
            )
        }
        row.cells.mapIndexed { j, c -> cell(raw, c, row.state, actionNames[j], effectNames, stateNames, payloadStates) }
    }

    return MachineDesc(
        packageName = raw.packageName,
        machine = raw.machine,
        stateType = raw.stateType,
        actionType = raw.actionType,
        effectType = raw.effectType,
        ctxType = raw.ctxType,
        initial = raw.initial,
        states = raw.states.map { Variant(it.name, it.hasPayload, it.fields) },
        actions = raw.actions.map { Variant(it.name, it.hasPayload, it.fields) },
        effects = raw.effects.map { Variant(it.name, it.hasPayload, it.fields) },
        rows = rows,
        prototypeModifiers = raw.prototypeModifiers,
        children = raw.children,
    )
}

private fun cell(
    raw: RawMachine,
    c: RawCell,
    state: String,
    action: String,
    effectNames: List<String>,
    stateNames: List<String>,
    payloadStates: Set<String>,
): CellDesc {
    fun checkEffects() = c.effects.forEach {
        if (it !in effectNames) {
            fail(
                "tabula::unknown-effect",
                "cell ($state, $action) emits `$it`, which is not a declared effect. " +
                    "Effects: ${effectNames.joinToString(" ")}"
            )
        }
    }

    return when (c.kind) {
        "IGNORE" -> CellDesc.Ignore
        "HANDLE" -> CellDesc.Handle
        "UNREACHABLE" -> CellDesc.Unreachable

        "GO" -> {
            if (c.target !in stateNames) {
                fail(
                    "tabula::unknown-state",
                    "cell ($state, $action) transitions to `${c.target}`, which is not a " +
                        "declared state. States: ${stateNames.joinToString(" ")}"
                )
            }
            // Rule R3. A GO cell is resolved entirely by the generator, so its
            // target must be constructible without developer code. Without
            // this, GO quietly becomes the lazy option and payloads fill up
            // with zero values chosen to avoid writing a cell.
            if (c.target in payloadStates && c.targetArgs.isBlank()) {
                fail(
                    "tabula::go-target",
                    "cell ($state, $action) uses GO to `${c.target}`, which carries a payload " +
                        "that cannot be derived from a literal. Use HANDLE, or supply literal " +
                        "arguments."
                )
            }
            checkEffects()
            CellDesc.Go(c.target, c.targetArgs, c.effects)
        }

        "EMIT" -> {
            if (c.effects.isEmpty()) {
                fail("tabula::empty-emit", "cell ($state, $action) uses EMIT with no effects; use IGNORE or HANDLE")
            }
            checkEffects()
            CellDesc.Emit(c.effects)
        }

        "DELEGATE" -> {
            if (raw.children.none { it.alias == c.child }) {
                fail(
                    "tabula::unknown-child",
                    "cell ($state, $action) delegates to `${c.child}`, which is not a declared " +
                        "child. Children: ${raw.children.joinToString(" ") { it.alias }}"
                )
            }
            CellDesc.Delegate(c.child)
        }

        else -> fail(
            "tabula::unknown-cell",
            "`${c.kind}` in row `$state`, column `$action`. Expected one of: " +
                "IGNORE, HANDLE, UNREACHABLE, GO, EMIT, DELEGATE."
        )
    }
}

/**
 * Reject a broken happy path before anything derives from it.
 *
 * Errors before features, and deliberately so: a default computed from an
 * invalid spine is worse than no default, because it produces a machine that
 * compiles and goes somewhere nobody wrote down.
 *
 * Runs before the row checks, so a spine is judged against the DECLARED states
 * rather than against whatever survived them. A machine with both a bad row
 * and a bad path reports the path first, which is the right order: the path is
 * the thing the developer added.
 *
 * See `spec/happy-paths.md`. Nothing here reaches `MachineDesc` -- these are
 * rejections, not data.
 */
private fun validatePaths(
    raw: RawMachine,
    stateNames: List<String>,
    actionNames: List<String>,
) {
    val seen = mutableSetOf<String>()
    for (path in raw.paths) {
        if (!seen.add(path.name)) {
            fail(
                "tabula::path-duplicate",
                "two paths are named `${path.name}`; a narrowed call site names " +
                    "the path it narrows to, so names must be unique"
            )
        }

        for (state in path.states) {
            if (state !in stateNames) {
                fail(
                    "tabula::path-unknown-state",
                    "path `${path.name}` names state `$state`, which is not declared. " +
                        "States: ${stateNames.joinToString(" ")}"
                )
            }
        }

        // Shape before content. A route is a sequence of hops, and a hop is a
        // state, an action and a state -- so the elements alternate and the
        // count is odd and at least three. Checking this first means the hop
        // walk below can index without guarding.
        if (path.elements.size < 3 || path.elements.size % 2 == 0) {
            fail(
                "tabula::path-broken",
                "path `${path.name}` has ${path.elements.size} element(s); a path " +
                    "alternates state and action, starting and ending with a state, " +
                    "so the count is odd and at least three"
            )
        }

        // Consecutive states must be connected by a real cell, which is what
        // keeps the declaration and the matrix from drifting -- the objection
        // to declaring a route away from the rows it describes.
        //
        // A HANDLE counts. Its target is not knowable from the matrix, and
        // supplying that target is exactly what the path is for; refusing it
        // here would reject the only cell kind the feature exists to shorten.
        for ((from, action, to) in path.hops) {
            val col = actionNames.indexOf(action)
            if (col < 0) {
                fail(
                    "tabula::path-unknown-state",
                    "path `${path.name}` names action `$action`, which is not " +
                        "declared. Actions: ${actionNames.joinToString(" ")}"
                )
            }
            val row = raw.rows.firstOrNull { it.state == from }
            val cell = row?.cells?.getOrNull(col)
            // THAT cell, not some cell in the row. A states-only spine could
            // only ask whether anything in the row reached `to`, so a HANDLE
            // anywhere made the row connect to anything. Naming the action is
            // what makes this precise.
            val ok = cell != null && (
                cell.kind == "HANDLE" || cell.kind == "DELEGATE" ||
                    (cell.kind == "GO" && cell.target == to)
                )
            if (!ok) {
                fail(
                    "tabula::path-broken",
                    "path `${path.name}` goes `$from` -`$action`-> `$to`, and cell " +
                        "($from, $action) cannot reach `$to`"
                )
            }
        }

        // A path that never ends is not a happy path, it is a loop with a name.
        val last = path.states.last()
        val lastRow = raw.rows.firstOrNull { it.state == last }
        val leaves = lastRow?.cells?.any { c ->
            c.kind == "HANDLE" || c.kind == "DELEGATE" ||
                (c.kind == "GO" && c.target != last)
        } ?: false
        if (leaves) {
            fail(
                "tabula::path-unterminated",
                "path `${path.name}` ends at `$last`, which can still be left; a " +
                    "path ends where the machine is done"
            )
        }
    }
}
