//! One hop of a happy path, and how `narrow` reads it.
//!
//! `spec/happy-paths.md`, "Settled before implementation": a hop
//! `from -action-> to` gets a narrowed call that takes the action that
//! ARRIVED in `from` and hands back either the happy state or what the matrix
//! did instead. Kotlin and Swift generate one named member per hop and one
//! case per outcome the `from` row can produce. `macro_rules!` can do neither
//! -- it cannot join identifiers into a new name, or deduplicate a set -- and
//! this crate takes no dependency to get round that. So Rust's surface is
//! generic over the hop's existing types, `narrow::<Connecting, Ready>(..)`,
//! and its other side is the machine's whole `State`: a `match` on it is still
//! exhaustive, so a new state still breaks every call site that matches, and
//! `?` is still the railway. What Rust gives up is precision -- a handler sees
//! states a given row cannot produce.

/// A happy-path hop, implemented by `transition_matrix!` on the hop's `from`
/// state for the hop's action: `impl Hop<Ready> for Connecting { type To = Live; .. }`.
///
/// Not for implementing by hand; the generated `narrow` is what uses it.
///
/// - `into_state`: This narrowed state, back as the machine's state.
/// - `happy`: `Ok` if `next` is the hop's happy state, the state reached otherwise.
pub trait Hop<A> {
    /// The machine's state type.
    type State;
    /// The state the hop leads to: the happy outcome.
    type To;

    fn into_state(self) -> Self::State;

    fn happy(next: Self::State) -> Result<Self::To, Self::State>;
}
