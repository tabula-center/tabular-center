package center.tabula

/**
 * The outcome of one matrix cell.
 *
 * [Stay] and [Ignored] are behaviourally identical and deliberately distinct:
 * `Ignored` means *the developer asserts this action is not applicable in this
 * state*; `Stay` means *the developer handled it and chose not to move*. The
 * lints and the coverage report treat them differently, so collapsing them
 * would lose real information.
 */
sealed interface Step<out S, out F> {
    /** Effects emitted, in order. */
    val effects: List<F>

    /** Transition to [next]. */
    data class Go<out S, out F>(
        val next: S,
        override val effects: List<F> = emptyList(),
    ) : Step<S, F>

    /** Handled; remain in the current state. */
    data class Stay<out F>(
        override val effects: List<F> = emptyList(),
    ) : Step<Nothing, F>

    /** Not applicable in this state; nothing happened. */
    data object Ignored : Step<Nothing, Nothing> {
        override val effects: List<Nothing> get() = emptyList()
    }

    companion object {
        /** Transition, emitting the listed effects. */
        fun <S, F> go(next: S, vararg effects: F): Step<S, F> = Go(next, effects.toList())

        /** Remain in place, emitting the listed effects. */
        fun <F> stay(vararg effects: F): Step<Nothing, F> = Stay(effects.toList())

        /** This action is not applicable here. */
        fun ignored(): Step<Nothing, Nothing> = Ignored
    }
}

/** The target state, if this step transitions. */
val <S> Step<S, *>.target: S?
    get() = (this as? Step.Go)?.next

/** Whether the cell declared the action inapplicable. */
val Step<*, *>.isIgnored: Boolean get() = this is Step.Ignored

/** Relabel the target state, keeping effects. Composition primitive. */
fun <S, T, F> Step<S, F>.mapState(f: (S) -> T): Step<T, F> = when (this) {
    is Step.Go -> Step.Go(f(next), effects)
    is Step.Stay -> this
    is Step.Ignored -> this
}

/**
 * Relabel the effects, keeping the outcome.
 *
 * Composition primitive: a `DELEGATE` cell lifts a child's effects into the
 * parent's vocabulary with this.
 */
fun <S, F, G> Step<S, F>.mapEffects(f: (F) -> G): Step<S, G> = when (this) {
    is Step.Go -> Step.Go(next, effects.map(f))
    is Step.Stay -> Step.Stay(effects.map(f))
    is Step.Ignored -> this
}
