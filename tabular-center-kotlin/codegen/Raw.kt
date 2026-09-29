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
data class RawPath(
    val name: String,
    val elements: List<String>,
    /** The action that walks this path backwards, or "" if it has none. */
    val back: String = "",
) {
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

    /**
     * The same hops, walked backwards: `(next, back) -> previous`.
     *
     * Empty when the path names no back action, which is why adding this
     * changes nothing for any machine that had one already.
     */
    val reverseHops: List<Triple<String, String, String>>
        get() = if (back.isBlank()) emptyList()
        else hops.map { (from, _, to) -> Triple(to, back, from) }
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
    /** See [MachineDesc.prototypeReceiver]. */
    val prototypeReceiver: String = "",
    /** See [MachineDesc.visibility]. */
    val visibility: String = "",
    /** See [MachineDesc.render]. */
    val render: RenderDesc? = null,
)

/** A variant as the processor reads it, before validation. */
data class RawVariant(
    val name: String,
    val hasPayload: Boolean = false,
    /** `name to type`, for `tabular-center::payload-hoist`. Optional. */
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
/**
 * A diagnostic from `spec/diagnostics.md`.
 *
 * [state] names the row being validated when it was raised, where one was.
 * It carries no position of its own -- this layer knows nothing about KSP,
 * syntax trees or files -- but it is enough for a front end to find the right
 * node: the KSP processor maps the state to its `@Row` annotation, so the
 * error lands on the row rather than on the annotated interface.
 */
class TabularCenterError(
    val code: String,
    override val message: String,
    val state: String? = null,
) : IllegalArgumentException(message)

/**
 * Run [body], tagging any diagnostic it raises with the row it came from.
 *
 * Done here rather than at each of the eighteen `fail` sites: the row is
 * known at exactly one place, the loop below, and a parameter threaded
 * through every validator would be eighteen chances to forget it.
 */
private inline fun <T> inRow(state: String, body: () -> T): T =
    try {
        body()
    } catch (e: TabularCenterError) {
        if (e.state == null) throw TabularCenterError(e.code, e.message, state) else throw e
    }

private fun fail(code: String, message: String): Nothing = throw TabularCenterError(code, "$code: $message")

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
            "tabular-center::unknown-state",
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
                "tabular-center::extra-row",
                "row `${row.state}` does not correspond to a declared state. " +
                    "States: ${stateNames.joinToString(" ")}"
            )
        if (row.state != expected) {
            fail(
                "tabular-center::missing-row",
                "row $i is `${row.state}` but `states` says `$expected`. " +
                    "Every state needs exactly one row, in declaration order. " +
                    "States: ${stateNames.joinToString(" ")}"
            )
        }
    }
    if (raw.rows.size < stateNames.size) {
        fail(
            "tabular-center::missing-row",
            "state `${stateNames[raw.rows.size]}` has no row. " +
                "Every state needs exactly one row, in declaration order. " +
                "States: ${stateNames.joinToString(" ")}"
        )
    }

    val rows = raw.rows.mapIndexed { i, row ->
        inRow(row.state) {
            if (row.cells.size != actionNames.size) {
                fail(
                    "tabular-center::row-arity",
                    "row `${row.state}` has ${row.cells.size} cells, expected ${actionNames.size}. " +
                        "Expected columns: ${actionNames.joinToString(" ")}"
                )
            }
            row.cells.mapIndexed { j, c ->
                cell(raw, derive(c, row.state, actionNames[j], raw), row.state, actionNames[j], effectNames, stateNames, payloadStates)
            }
        }
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
        prototypeReceiver = raw.prototypeReceiver,
        visibility = raw.visibility,
        render = raw.render,
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
    fun checkEffects() = c.effects.map { effectName(it) }.forEach {
        if (it !in effectNames) {
            fail(
                "tabular-center::unknown-effect",
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
                    "tabular-center::unknown-state",
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
                    "tabular-center::go-target",
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
                fail("tabular-center::empty-emit", "cell ($state, $action) uses EMIT with no effects; use IGNORE or HANDLE")
            }
            checkEffects()
            CellDesc.Emit(c.effects)
        }

        "DELEGATE" -> {
            if (raw.children.none { it.alias == c.child }) {
                fail(
                    "tabular-center::unknown-child",
                    "cell ($state, $action) delegates to `${c.child}`, which is not a declared " +
                        "child. Children: ${raw.children.joinToString(" ") { it.alias }}"
                )
            }
            CellDesc.Delegate(c.child)
        }

        else -> fail(
            "tabular-center::unknown-cell",
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
                "tabular-center::path-duplicate",
                "two paths are named `${path.name}`; a narrowed call site names " +
                    "the path it narrows to, so names must be unique"
            )
        }

        for (state in path.states) {
            if (state !in stateNames) {
                fail(
                    "tabular-center::path-unknown-state",
                    "path `${path.name}` names state `$state`, which is not declared. " +
                        "States: ${stateNames.joinToString(" ")}"
                )
            }
        }

        // The back action, if there is one, is an action like any other. Same
        // code as an unknown state: a path that names something the machine
        // does not declare is the same mistake whichever column it is in.
        if (path.back.isNotBlank() && path.back !in actionNames) {
            fail(
                "tabular-center::path-unknown-state",
                "path `${path.name}` walks back by `${path.back}`, which is not a " +
                    "declared action. Actions: ${actionNames.joinToString(" ")}"
            )
        }

        // Shape before content. A route is a sequence of hops, and a hop is a
        // state, an action and a state -- so the elements alternate and the
        // count is odd and at least three. Checking this first means the hop
        // walk below can index without guarding.
        if (path.elements.size < 3 || path.elements.size % 2 == 0) {
            fail(
                "tabular-center::path-broken",
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
                    "tabular-center::path-unknown-state",
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
                    "tabular-center::path-broken",
                    "path `${path.name}` goes `$from` -`$action`-> `$to`, and cell " +
                        "($from, $action) cannot reach `$to`"
                )
            }
        }

        // A path that never ends is not a happy path, it is a loop with a name.
        //
        // Walking BACK is not leaving: a path with a `back` action is
        // travelled in both directions, so its own back column does not count
        // against the ending. Without this, every wizard that can go back
        // would be reported unterminated -- which is what the first version
        // did, and what its own test caught.
        val last = path.states.last()
        val lastRow = raw.rows.firstOrNull { it.state == last }
        val leaves = lastRow?.cells?.withIndex()?.any { (j, c) ->
            val action = actionNames.getOrNull(j)
            if (path.back.isNotBlank() && action == path.back) {
                false
            } else {
                c.kind == "HANDLE" || c.kind == "DELEGATE" ||
                    (c.kind == "GO" && c.target != last)
            }
        } ?: false
        if (leaves) {
            fail(
                "tabular-center::path-unterminated",
                "path `${path.name}` ends at `$last`, which can still be left; a " +
                    "path ends where the machine is done"
            )
        }
    }
}

/**
 * A `HANDLE` named by a hop becomes a `GO` to that hop's next state.
 *
 * The half of `spec/happy-paths.md` that motivated the feature: on the happy
 * path the common case stops being typed at all. A developer declares the
 * route once and the cells along it are written by the generator.
 *
 * Only `HANDLE`. A `GO` already says where it goes, and rewriting it would let
 * a path silently contradict a cell -- the developer would have written two
 * answers and been told neither. `tabular-center::path-broken` already rejects a hop
 * whose `GO` disagrees, so by the time this runs the two agree or the build
 * stopped.
 *
 * The result is indistinguishable from the longhand machine, which is the
 * additive test: a derived `GO(to)` and a written `GO(to)` are the same
 * `CellDesc`, so `TABLE`, `.grid`, `.lint`, `.cov` and `.mmd` are byte-identical
 * either way. Nothing downstream can tell which was written.
 *
 * Runs after `validatePaths`, so a hop is known to name a real cell before
 * anything is derived from it. Deriving from an invalid spine would produce a
 * machine that compiles and goes somewhere nobody wrote down.
 */
private fun derive(c: RawCell, state: String, action: String, raw: RawMachine): RawCell {
    if (c.kind != "HANDLE") return c
    // Forward hops first, then the reverse ones a `back` action declares.
    // Both derive over HANDLE cells only, so an explicit cell always wins and
    // a machine that declares no path is untouched.
    val to = raw.paths
        .flatMap { it.hops + it.reverseHops }
        .firstOrNull { it.first == state && it.second == action }
        ?.third
        ?: return c
    return c.copy(kind = "GO", target = to)
}
