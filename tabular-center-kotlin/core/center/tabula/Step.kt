// `Step`, the value every cell returns -- a transition, a stay or an ignore,
// with its effects -- and the operations that compose steps
// (spec/cells.md 6).
//
// - `target`: The target state, if this step transitions.
// - `isIgnored`: Whether the cell declared the action inapplicable.
// - `mapEffects`: Relabel the effects, keeping the outcome.
package center.tabula

/**
 * The outcome of one matrix cell.
 *
 * [Stay] and [Ignored] are behaviourally identical and deliberately distinct:
 * `Ignored` means *the developer asserts this action is not applicable in this
 * state*; `Stay` means *the developer handled it and chose not to move*. The
 * lints and the coverage report treat them differently, so collapsing them
 * would lose real information.
 *
 * A step is a value, and it composes (spec/cells.md 6):
 *
 * - `map(f)` applies `f` to a [Go] target; [Stay] and [Ignored] pass through.
 * - `flatMap(f)` runs `f` on a [Go] target and returns `f`'s step, with this
 *   step's effects followed by `f`'s. [Stay] and [Ignored] short-circuit
 *   without calling `f`. An [Ignored] from `f` absorbs: the result is
 *   [Ignored], with no effects.
 * - `zip(other, transform)` is `flatMap { x -> other.map { y -> transform(x, y) } }`,
 *   and `zip(other)` pairs the targets. When this step is not [Go], `other`'s
 *   effects are dropped.
 *
 * ```
 * fun enter(s: S): Step<S, F> =
 *     if (s == S.Validating) Step.go(s, F.Fetch) else Step.go(s)
 *
 * Step.go(S.Validating, F.Log).flatMap(::enter)   // Go(Validating, [Log, Fetch])
 * ```
 *
 * - `effects`: Effects emitted, in order.
 * - `go`: Transition, emitting the listed effects.
 * - `stay`: Remain in place, emitting the listed effects.
 * - `ignored`: This action is not applicable here.
 */
sealed interface Step<out S, out F> {
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
        fun <S, F> go(next: S, vararg effects: F): Step<S, F> = Go(next, effects.toList())

        fun <F> stay(vararg effects: F): Step<Nothing, F> = Stay(effects.toList())

        fun ignored(): Step<Nothing, Nothing> = Ignored
    }
}

val <S> Step<S, *>.target: S?
    get() = (this as? Step.Go)?.next

val Step<*, *>.isIgnored: Boolean get() = this is Step.Ignored

fun <S, T, F> Step<S, F>.map(f: (S) -> T): Step<T, F> = when (this) {
    is Step.Go -> Step.Go(f(next), effects)
    is Step.Stay -> this
    is Step.Ignored -> this
}

@Deprecated("Use map", ReplaceWith("map(f)"))
fun <S, T, F> Step<S, F>.mapState(f: (S) -> T): Step<T, F> = map(f)

fun <S, T, F> Step<S, F>.flatMap(f: (S) -> Step<T, F>): Step<T, F> = when (this) {
    is Step.Go -> when (val then = f(next)) {
        is Step.Go -> Step.Go(then.next, effects + then.effects)
        is Step.Stay -> Step.Stay(effects + then.effects)
        is Step.Ignored -> Step.Ignored
    }
    is Step.Stay -> this
    is Step.Ignored -> this
}

fun <S, T, U, F> Step<S, F>.zip(other: Step<T, F>, transform: (S, T) -> U): Step<U, F> =
    flatMap { x -> other.map { y -> transform(x, y) } }

fun <S, T, F> Step<S, F>.zip(other: Step<T, F>): Step<Pair<S, T>, F> =
    zip(other) { x, y -> x to y }

fun <S, F, G> Step<S, F>.mapEffects(f: (F) -> G): Step<S, G> = when (this) {
    is Step.Go -> Step.Go(next, effects.map(f))
    is Step.Stay -> Step.Stay(effects.map(f))
    is Step.Ignored -> this
}
