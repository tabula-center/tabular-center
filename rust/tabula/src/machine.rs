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

/// One effect variant's handler.
///
/// The generated `Handlers` bundle names one `Perform` bound per effect
/// variant, so **adding a variant breaks every handler's build**. That is the
/// same required-member mechanism the transition side uses, applied to the
/// other half of the machine.
///
/// No other library in this space offers total effect handling. It falls out
/// for free here: once effects are a generated sum type, the generator knows
/// the variants, and knowing the variants is the whole trick.
///
/// `EV` is the *narrowed* effect variant, so a handler receives its payload
/// already destructured — the same treatment cells get.
pub trait Perform<M: Machine, EV> {
    /// Carry out the effect, optionally producing a follow-up action.
    ///
    /// The action is returned as **data**. The driver enqueues it; a handler
    /// is given no way back into `step`, which is what makes re-entrancy
    /// impossible rather than merely discouraged. See [`crate::driver`].
    fn perform(&mut self, ctx: &mut M::Ctx, effect: EV) -> Option<M::Action>;
}
