package codegen

/**
 * The machine description a generator emits from.
 *
 * ## Why this exists as a separate type
 *
 * KSP is a Maven artifact, and the environment this was built in cannot reach
 * Maven. Rather than ship an unrunnable processor, the generator is split:
 *
 * - **This package** turns a [MachineDesc] into Kotlin source. Pure, no KSP,
 *   no compiler plugin, fully testable — and tested by emitting the reference
 *   machine, diffing it against a committed golden file, *compiling* the
 *   result, and then compiling a deliberately incomplete implementation
 *   against it to confirm the guarantee survives generation.
 * - **The KSP processor** reads annotations, builds a [MachineDesc], and calls
 *   [emit]. Mechanical, and small enough to review by eye.
 *
 * That split is worth keeping even once KSP runs. A code generator whose logic
 * can only be exercised through a compiler plugin is a generator nobody
 * refactors.
 */
data class MachineDesc(
    val packageName: String,
    val machine: String,
    val stateType: String,
    val actionType: String,
    val effectType: String,
    val ctxType: String,
    val initial: String,
    val states: List<Variant>,
    val actions: List<Variant>,
    val effects: List<Variant>,
    val rows: List<List<CellDesc>>,
    /** Copied verbatim onto every generated cell member. See ARCHITECTURE §5. */
    val prototypeModifiers: List<String> = emptyList(),
    /** Child machines reached by `DELEGATE`, in first-appearance order. */
    val children: List<ChildDesc> = emptyList(),
    /**
     * The prototype's extension receiver, as a type, or empty for none.
     *
     * Part of the color, like [prototypeModifiers]: `fun Clock.handle(...)`
     * makes every cell member, every effect handler, `step` and `perform`
     * extensions on `Clock`, so a cell body can call the receiver's members
     * and a caller must have one in scope to dispatch at all. See
     * ARCHITECTURE §5.
     */
    val prototypeReceiver: String = "",
    /**
     * Visibility of every generated top-level declaration: empty for public,
     * or `internal`.
     *
     * Read from the annotated declaration, not the prototype. The generated
     * surface names the machine's own types, so it can be no more visible than
     * they are -- a public `Cells` over internal `S` is `exposes its internal
     * parameter type`, a compile error in generated code the user never wrote.
     */
    val visibility: String = "",
) {
    init {
        require(rows.size == states.size) {
            "tabula::missing-row: ${rows.size} rows for ${states.size} states"
        }
        require(prototypeReceiver.isEmpty() || children.isEmpty()) {
            "tabula: a prototype extension receiver on a machine with DELEGATE " +
                "cells is not supported yet; the child's step would need the same " +
                "receiver threaded through the lens"
        }
        rows.forEachIndexed { i, row ->
            require(row.size == actions.size) {
                "tabula::row-arity: row `${states[i].name}` has ${row.size} cells, " +
                    "expected ${actions.size} (${actions.joinToString(" ") { it.name }})"
            }
        }
    }
}

/**
 * One variant of a sealed hierarchy.
 *
 * [fields] is `name to type` for a payload-carrying variant. It exists only to
 * feed `tabula::payload-hoist`, so it may be empty even when [hasPayload] is
 * true — a processor that cannot resolve a type still produces a usable
 * machine, just without that one lint.
 */
data class Variant(
    val name: String,
    val hasPayload: Boolean = false,
    val fields: List<Pair<String, String>> = emptyList(),
)

/**
 * A child machine referenced by one or more `DELEGATE` cells.
 *
 * Two names, for two jobs. [alias] is what a `DELEGATE` cell names and what
 * the parent's generated MEMBERS are built from -- `retryChildState`,
 * `delegateToRetry` -- so it must be an identifier. [packageName] is where the
 * child's generated surface lives, and every reference to it is qualified by
 * it: `generated.retry.Cells`, `generated.retry.step`, `generated.retry.S`.
 *
 * Qualified rather than imported: the generated file imports only
 * `dev.tabula`, so it cannot collide with anything the parent's package
 * declares. Until the September 2026 audit the emitter qualified with the
 * alias, which only worked for a child in a root package named exactly like
 * the alias, and [packageName] went unused.
 */
data class ChildDesc(
    val alias: String,
    val packageName: String,
    val stateType: String,
    val actionType: String,
    val effectType: String,
    val ctxType: String,
)

/** One cell, as the generator sees it. */
sealed interface CellDesc {
    data object Ignore : CellDesc
    data object Handle : CellDesc
    data object Unreachable : CellDesc
    data class Go(val target: String, val targetArgs: String = "", val effects: List<String> = emptyList()) : CellDesc
    data class Emit(val effects: List<String>) : CellDesc
    data class Delegate(val child: String) : CellDesc
}
