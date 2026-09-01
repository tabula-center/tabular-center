//! Composition: driving a child machine from one cell of a parent's matrix.
//!
//! # The property this exists to deliver
//!
//! > Scoping a total child into a total parent yields a total parent, and the
//! > compiler proves it by the same mechanism as everything else.
//!
//! `DELEGATE!(child)` is not a nicer `HANDLE`. The generated cell *calls the
//! child's `step`*, so the parent's bound set includes the child's entire cell
//! surface (`child::Cells`). A hole anywhere in the child breaks the parent's
//! build. `HANDLE` could never give that: a hand-written body is free to
//! ignore the child entirely.
//!
//! # Coverage is never inherited silently
//!
//! The parent row still lists every column. You can see at a glance which
//! cells delegate. A parent does not get to say "everything else goes to the
//! child" -- that would be exactly the wildcard this library exists to remove,
//! wearing a different hat.
//!
//! # The three operations, and where they went
//!
//! ARCHITECTURE section 8 names three: *nest* (child state is a field of
//! parent state), *alternate* (child state **is** one case of parent state),
//! and *translate* (relabel a generic machine into a domain vocabulary).
//!
//! They are not three APIs. They are the five methods of [`Delegate`]:
//!
//! | Operation | Where |
//! |---|---|
//! | nest / alternate | [`Lens::child_state`] + [`Lens::embed`] |
//! | translate (effects) | [`Lens::lift`] |
//! | context plumbing | [`Lens::child_ctx`] |
//! | translate (actions) | [`Delegate::to_child`] — the prism |
//!
//! # Why two traits
//!
//! The lens is a property of the *(parent state, child)* pair; only the action
//! prism differs per cell. An earlier version put all five on one trait,
//! instantiated per cell, which meant two delegate cells to the same child
//! repeated four identical methods.
//!
//! The Kotlin implementation made this obvious — it names members, so the
//! duplication was visible as four functions with the same body — and the
//! finding was folded back here. That is the argument for writing the same
//! thing twice: the second implementation is a review of the first.
//!
//! Nest and alternate collapse into one because a `DELEGATE` cell lives on a
//! *row*, and the row already is the parent state case. The distinction only
//! mattered when composition was an operator applied to whole machines.
//!
//! Closure pairs rather than key paths, per ARCHITECTURE: Swift key paths cost
//! real performance and Swift has no native case key paths. Here they are
//! trait methods, which monomorphise to nothing.
//!
//! # Color flows one way, by construction
//!
//! A colorless child composes into a colored parent. The reverse does not: the
//! generated cell would need `.await` inside a non-`async` `step`, and rustc
//! rejects it. No check to write, and nothing to circumvent.

use crate::machine::Machine;

/// How a child machine sits inside one parent state.
///
/// Written **once per (parent state, child)**, however many cells of that row
/// delegate. `M` is the parent machine, `SV` the parent's narrowed state
/// variant, `CM` the child machine's marker (`child::Marker`).
pub trait Lens<M: Machine, SV, CM: Machine> {
    /// Read the child's state out of the parent's. Half of the lens.
    fn child_state(&mut self, state: &SV) -> CM::State;

    /// Put the child's state back into the parent's. The other half.
    ///
    /// Returns the full parent state rather than the narrowed variant, so a
    /// delegate may move the parent elsewhere on a child transition — a child
    /// reaching its terminal state is often the parent's cue to leave.
    fn embed(&mut self, state: SV, child: CM::State) -> M::State;

    /// Lift a child effect into the parent's vocabulary.
    fn lift(&mut self, effect: CM::Effect) -> M::Effect;

    /// Hand the child its context.
    ///
    /// When the parent's context *contains* the child's this is a field
    /// access, which is the shape to aim for: the child then never sees parent
    /// data it has no business with.
    fn child_ctx<'a>(&mut self, ctx: &'a mut M::Ctx) -> &'a mut CM::Ctx;
}

/// One `DELEGATE` cell: which child action this parent action means.
///
/// The only part of composition that is genuinely per cell. Everything else is
/// [`Lens`].
pub trait Delegate<M: Machine, SV, AV, CM: Machine>: Lens<M, SV, CM> {
    /// Translate the parent action into a child action.
    ///
    /// `None` means this action has no meaning for the child, and the cell
    /// reports [`crate::Outcome::Ignored`]. That is the honest answer for a
    /// parent action the child's alphabet does not contain, and it keeps the
    /// `IGNORE` / `Stay` distinction intact.
    fn to_child(&mut self, ctx: &mut M::Ctx, state: &SV, action: AV) -> Option<CM::Action>;
}

/// Implements [`Lens`] for the common shape: the parent state's payload holds
/// the child state in a named field, and the parent's context contains the
/// child's.
///
/// `to_child` and `lift` stay hand-written — those two encode real decisions,
/// and deriving them would mean guessing.
///
/// ```ignore
/// delegate_lens! {
///     impl Lens<job::Job, Retrying, retry::Marker> for Cells {
///         field child;
///         ctx   retry;
///         embed |s, cs| lift_child(cs);
///         lift  |e| lift_effect(e);
///     }
/// }
/// ```
#[macro_export]
macro_rules! delegate_lens {
    (
        impl Lens<$m:ty, $sv:ty, $cm:ty> for $me:ty {
            field $f:ident;
            ctx   $c:ident;
            embed |$es:pat_param, $ec:pat_param| $embed:expr;
            lift  |$le:pat_param| $lift:expr;
        }
    ) => {
        impl $crate::Lens<$m, $sv, $cm> for $me {
            fn child_state(&mut self, state: &$sv) -> <$cm as $crate::Machine>::State {
                state.$f
            }

            fn embed(
                &mut self,
                $es: $sv,
                $ec: <$cm as $crate::Machine>::State,
            ) -> <$m as $crate::Machine>::State {
                $embed
            }

            fn lift(
                &mut self,
                $le: <$cm as $crate::Machine>::Effect,
            ) -> <$m as $crate::Machine>::Effect {
                $lift
            }

            fn child_ctx<'a>(
                &mut self,
                ctx: &'a mut <$m as $crate::Machine>::Ctx,
            ) -> &'a mut <$cm as $crate::Machine>::Ctx {
                &mut ctx.$c
            }
        }
    };
}
