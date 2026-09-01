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
