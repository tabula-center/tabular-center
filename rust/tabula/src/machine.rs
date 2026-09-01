//! The cell surface, expressed as trait bounds.
//!
//! `macro_rules!` cannot concatenate identifiers, so the Rust implementation
//! cannot synthesize a member named `idle_start` from `Idle` and `Start`. It
//! expresses the cell surface as *trait bounds* instead:
//!
//! ```ignore
//! impl Handle<Timer, Idle, Start> for MyTimer { /* ... */ }
//! ```
//!
//! A missing cell surfaces as `the trait bound `MyTimer: Handle<Timer, Idle,
//! Start>` is not satisfied`, which names the exact hole. Same guarantee,
//! different spelling. Kotlin and Swift keep named members, because KSP and
//! SwiftSyntax *can* build identifiers.

use crate::step::Step;

/// Ties a machine's four types together so [`Handle`] needs three parameters
/// rather than six.
///
/// Implemented by the generated marker type named in the `machine` clause.
pub trait Machine {
    /// The machine's state sum type.
    type State;
    /// The machine's action sum type.
    type Action;
    /// The machine's effect sum type.
    type Effect;
    /// Cross-state data. Rule R4: payload is state-local, `Ctx` outlives
    /// transitions.
    type Ctx;
}

/// One `HANDLE` cell.
///
/// `SV` and `AV` are the *narrowed* variant types, so an implementation
/// receives payloads already destructured and non-optional. There is no `if
/// let`, no `matches!`, and no unwrap anywhere in a cell body -- which is the
/// thing that is impractical to write by hand once a matrix gets large.
pub trait Handle<M: Machine, SV, AV> {
    /// Decide what happens for this `(state, action)` pair.
    fn handle(&mut self, ctx: &mut M::Ctx, state: SV, action: AV) -> Step<M::State, M::Effect>;
}
