package dev.tabula

/**
 * One entry in the transition matrix, as inert data.
 *
 * Six kinds, split three and three. The *static* kinds ([Ignore], [Go], [Emit])
 * are resolved entirely by the generator and produce no required member. This
 * is what makes a large matrix survivable: the boring 60-70% of cells that just
 * mean "not applicable here" cost one word each.
 */
sealed interface Cell {
    /** No-op. The action is not applicable in this state. */
    data object Ignore : Cell

    /**
     * Unconditional transition. The target must be statically constructible:
     * payload-free, or built from literals. See ARCHITECTURE rule R3.
     */
    data class Go(val target: String, val effects: List<String> = emptyList()) : Cell

    /** Remain in the current state, emitting the listed effects. */
    data class Emit(val effects: List<String>) : Cell

    /** Generates a required member; the developer writes the body. */
    data object Handle : Cell

    /**
     * Forward to a composed child machine.
     *
     * Written out explicitly, one cell at a time: a parent never inherits
     * coverage wholesale from a child.
     */
    data class Delegate(val child: String) : Cell

    /**
     * The developer asserts this pair cannot occur; compiles to a trap.
     *
     * Generates no member — writing `UNREACHABLE` *is* the statement of intent
     * — but the coverage report counts them, because a machine with many
     * usually has a modelling error.
     */
    data object Unreachable : Cell
}

/** Whether the generator resolves this cell entirely, with no developer code. */
val Cell.isStatic: Boolean
    get() = this is Cell.Ignore || this is Cell.Go || this is Cell.Emit

/**
 * Whether this cell contributes a required member.
 *
 * Sum it over the matrix and you have the number of things the developer must
 * implement. This is the predicate the guarantee rests on.
 */
val Cell.generatesMember: Boolean
    get() = this is Cell.Handle || this is Cell.Delegate

/** The target state variant, if this cell transitions unconditionally. */
val Cell.staticTarget: String?
    get() = (this as? Cell.Go)?.target

/** Effects this cell emits unconditionally. */
val Cell.staticEffects: List<String>
    get() = when (this) {
        is Cell.Go -> effects
        is Cell.Emit -> effects
        else -> emptyList()
    }

/** Lowercase kind name, as used in diagnostics and the conformance format. */
val Cell.kindName: String
    get() = when (this) {
        is Cell.Ignore -> "ignore"
        is Cell.Go -> "go"
        is Cell.Emit -> "emit"
        is Cell.Handle -> "handle"
        is Cell.Delegate -> "delegate"
        is Cell.Unreachable -> "unreachable"
    }
