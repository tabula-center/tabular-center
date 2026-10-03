//~ EXPECT: 'when' expression must be exhaustive
//
// The free second guarantee, the Kotlin counterpart of rustc's exhaustiveness
// check on the generated `match`. Adding a state to the sealed hierarchy breaks
// the generated dispatcher — so a stale generated file cannot silently ignore
// a new state.
//
// This fixture reproduces the generated dispatcher inline, because the real one
// is regenerated from the annotations and would simply grow the branch.
package cf2

import center.tabula.*

sealed interface S {
    data object Idle : S
    data object Running : S
    data object Paused : S
}

sealed interface A {
    data object Go : A
}

fun step(s: S, a: A): Step<S, Nothing> = when (s) {
    is S.Idle -> when (a) { is A.Go -> Step.Go(S.Running) }
    is S.Running -> when (a) { is A.Go -> Step.Go(S.Idle) }
}
