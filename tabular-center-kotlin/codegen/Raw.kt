package center.tabula.codegen

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
    val back: String = "",
) {
    val states: List<String> get() = elements.filterIndexed { i, _ -> i % 2 == 0 }

    val actions: List<String> get() = elements.filterIndexed { i, _ -> i % 2 == 1 }

    val hops: List<Triple<String, String, String>>
        get() = if (elements.size < 3 || elements.size % 2 == 0) emptyList()
        else (0 until elements.size / 2).map {
            Triple(elements[it * 2], elements[it * 2 + 1], elements[it * 2 + 2])
        }

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
    val states: List<RawVariant>,
    val actions: List<RawVariant>,
    val effects: List<RawVariant>,
    val rows: List<RawRow>,
    val prototypeModifiers: List<String> = emptyList(),
    val children: List<ChildDesc> = emptyList(),
    val paths: List<RawPath> = emptyList(),
    val prototypeReceiver: String = "",
    val visibility: String = "",
    val render: RenderDesc? = null,
)

/** A variant as the processor reads it, before validation. */
data class RawVariant(
    val name: String,
    val hasPayload: Boolean = false,
    val fields: List<Pair<String, String>> = emptyList(),
)

/** One `@Row`: the state it belongs to, then one cell per action. */
data class RawRow(val state: String, val cells: List<RawCell>)

/** One `@CellSpec`, before validation. */
data class RawCell(
    val kind: String,
    val target: String = "",
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

private inline fun <T> inRow(state: String, body: () -> T): T =
    try {
        body()
    } catch (e: TabularCenterError) {
        if (e.state == null) throw TabularCenterError(e.code, e.message, state) else throw e
    }

private fun fail(code: String, message: String): Nothing = throw TabularCenterError(code, "$code: $message")

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

    val desc = MachineDesc(
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
        hops = hopsOf(raw),
    )
    checkMemberCollisions(desc)
    return desc
}

private fun hopsOf(raw: RawMachine): List<HopDesc> {
    val state = raw.states.map { it.name }
    val action = raw.actions.map { it.name }
    return raw.paths.flatMap { it.hops }
        .map { (f, a, t) -> HopDesc(state.indexOf(f), action.indexOf(a), state.indexOf(t)) }
        .distinctBy { it.from to it.action }
}

private fun checkMemberCollisions(d: MachineDesc) {
    val seen = HashMap<String, GeneratedMember>()
    for (m in cellsMembers(d)) {
        val first = seen.putIfAbsent(m.name, m) ?: continue
        throw TabularCenterError(
            "tabular-center::member-collision",
            "tabular-center::member-collision: ${first.origin} and ${m.origin} would both " +
                "generate the member `${m.name}`. Rename a state, an action or an effect so " +
                "the two differ.",
            m.state ?: first.state,
        )
    }
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

        if (path.back.isNotBlank() && path.back !in actionNames) {
            fail(
                "tabular-center::path-unknown-state",
                "path `${path.name}` walks back by `${path.back}`, which is not a " +
                    "declared action. Actions: ${actionNames.joinToString(" ")}"
            )
        }

        if (path.elements.size < 3 || path.elements.size % 2 == 0) {
            fail(
                "tabular-center::path-broken",
                "path `${path.name}` has ${path.elements.size} element(s); a path " +
                    "alternates state and action, starting and ending with a state, " +
                    "so the count is odd and at least three"
            )
        }

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

private fun derive(c: RawCell, state: String, action: String, raw: RawMachine): RawCell {
    if (c.kind != "HANDLE") return c
    val to = raw.paths
        .flatMap { it.hops + it.reverseHops }
        .firstOrNull { it.first == state && it.second == action }
        ?.third
        ?: return c
    return c.copy(kind = "GO", target = to)
}
