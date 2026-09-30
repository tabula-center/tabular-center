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
    /**
     * The rendering prototype, or null for a machine without one. See
     * [RenderDesc] and ARCHITECTURE §9.
     *
     * Null is the default and emits nothing, so every machine declared before
     * the rendering surface existed generates exactly what it did.
     */
    val render: RenderDesc? = null,
    /**
     * The forward hops of every declared path, deduplicated by
     * `(from, action)`: two paths through one hop share one narrowed member.
     * Empty for a machine without paths, which then emits exactly what it did
     * before the narrowed surface existed. See [HopDesc].
     */
    val hops: List<HopDesc> = emptyList(),
) {
    init {
        require(rows.size == states.size) {
            "tabular-center::missing-row: ${rows.size} rows for ${states.size} states"
        }
        require(prototypeReceiver.isEmpty() || children.isEmpty()) {
            "tabular-center: a prototype extension receiver on a machine with DELEGATE " +
                "cells is not supported yet; the child's step would need the same " +
                "receiver threaded through the lens"
        }
        rows.forEachIndexed { i, row ->
            require(row.size == actions.size) {
                "tabular-center::row-arity: row `${states[i].name}` has ${row.size} cells, " +
                    "expected ${actions.size} (${actions.joinToString(" ") { it.name }})"
            }
        }
    }
}

/**
 * The rendering surface's prototype: `S -> UI`, declared separately from the
 * transition prototype. ARCHITECTURE §9, PLAN Phase 9b.
 *
 * It generates one required member per STATE -- not per cell -- each taking
 * its state already narrowed, and a `render` dispatcher that is an exhaustive
 * `when` over the states. Its color is its own: [modifiers] are copied onto
 * every render member and onto `render`, exactly as the transition
 * prototype's are onto cells, and the two are independent. That is the point
 * of a second prototype -- `@Composable` belongs here, where recomposition
 * may call a member any number of times, and never on a transition, which
 * would then run whenever Compose chose to recompose.
 *
 * No extension receiver yet: the dispatcher would have to thread one through,
 * as `step` does for the transition prototype. Refused at extraction rather
 * than generated wrong.
 */
data class RenderDesc(
    /** Copied verbatim onto every render member and onto `render`. */
    val modifiers: List<String> = emptyList(),
    /** What a render member returns: `Unit` for a composable, a view type otherwise. */
    val returnType: String = "Unit",
)

/**
 * One hop of a happy path, `from -action-> to`, as indices into
 * [MachineDesc.states] and [MachineDesc.actions]. spec/happy-paths.md,
 * "Settled before implementation": it generates a narrowed member that takes
 * the action that ARRIVED in `from`, and a sealed outcome type with one variant
 * per state the `from` row can produce -- `to` the happy one.
 */
data class HopDesc(val from: Int, val action: Int, val to: Int)

/**
 * One variant of a sealed hierarchy.
 *
 * [fields] is `name to type` for a payload-carrying variant. It exists only to
 * feed `tabular-center::payload-hoist`, so it may be empty even when [hasPayload] is
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
 * `dev.tabularcenter`, so it cannot collide with anything the parent's package
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

/**
 * An effect reference without its arguments: `StopClock(reason = X)` names the
 * effect `StopClock`.
 *
 * Which effect a cell emits is what validation and `TABLE` are about; with
 * what is the dispatcher's business, and it emits the reference verbatim.
 */
fun effectName(ref: String): String = ref.substringBefore('(')
