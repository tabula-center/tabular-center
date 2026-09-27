//! The outcome of one matrix cell.
//!
//! A cell returns a [`Step`], which is an [`Outcome`] plus a bounded collection
//! of effects. Nothing here allocates, so the whole type works under `no_std`
//! with the state machine resident in ROM.

use core::fmt;

/// Default effect capacity per step.
///
/// Two is deliberately small. A cell that wants to emit more than two effects
/// is usually a cell that wants splitting, and the ceiling makes that visible.
/// Machines that genuinely need more set `K` explicitly.
pub const DEFAULT_EFFECT_CAPACITY: usize = 2;

/// What a cell decided.
///
/// [`Outcome::Stay`] and [`Outcome::Ignored`] are behaviourally identical and
/// deliberately distinct in the source:
///
/// - `Ignored` means *the developer asserts this action is not applicable in
///   this state.*
/// - `Stay` means *the developer handled it and chose not to move.*
///
/// The introspection layer reports them differently and the reachability
/// linter treats them differently, so collapsing them would lose real
/// information. See ARCHITECTURE.md section 2.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Outcome<S> {
    /// Transition to `S`.
    Go(S),
    /// Handled; remain in the current state.
    Stay,
    /// Not applicable in this state; nothing happened.
    Ignored,
}

impl<S> Outcome<S> {
    /// The target state, if this outcome transitions.
    pub fn target(self) -> Option<S> {
        match self {
            Outcome::Go(s) => Some(s),
            Outcome::Stay | Outcome::Ignored => None,
        }
    }

    /// Relabel the target state. Used by the `translate` composition operator.
    pub fn map<T, G: FnOnce(S) -> T>(self, g: G) -> Outcome<T> {
        match self {
            Outcome::Go(s) => Outcome::Go(g(s)),
            Outcome::Stay => Outcome::Stay,
            Outcome::Ignored => Outcome::Ignored,
        }
    }
}

/// Raised when a step emits more effects than its capacity allows.
///
/// Carries the rejected effect back so a caller that wants to recover can.
pub struct CapacityError<F> {
    /// The effect that did not fit.
    pub rejected: F,
    /// The capacity that was exceeded.
    pub capacity: usize,
}

impl<F> fmt::Debug for CapacityError<F> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "CapacityError {{ capacity: {} }}", self.capacity)
    }
}

impl<F> fmt::Display for CapacityError<F> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "tabula: effect capacity {} exceeded; raise K on Step<S, F, K>",
            self.capacity
        )
    }
}

/// A bounded, allocation-free collection of effects.
#[derive(Clone, PartialEq, Eq)]
pub struct Effects<F, const K: usize = DEFAULT_EFFECT_CAPACITY> {
    items: [Option<F>; K],
    len: usize,
}

impl<F, const K: usize> Effects<F, K> {
    /// An empty collection.
    pub fn none() -> Self {
        Self {
            items: core::array::from_fn(|_| None),
            len: 0,
        }
    }

    /// A collection holding a single effect.
    pub fn one(effect: F) -> Self {
        let mut e = Self::none();
        e.push(effect);
        e
    }

    /// Append an effect.
    ///
    /// # Panics
    /// If the capacity `K` is exceeded. Capacity is a compile-time property of
    /// the machine, so overflow is a programming error rather than a runtime
    /// condition; use [`Effects::try_push`] where that is not true.
    pub fn push(&mut self, effect: F) {
        if self.try_push(effect).is_err() {
            panic!("tabula: effect capacity {K} exceeded; raise K on Step<S, F, K>");
        }
    }

    /// Append an effect, returning it back if there is no room.
    pub fn try_push(&mut self, effect: F) -> Result<(), CapacityError<F>> {
        if self.len >= K {
            return Err(CapacityError {
                rejected: effect,
                capacity: K,
            });
        }
        self.items[self.len] = Some(effect);
        self.len += 1;
        Ok(())
    }

    /// Number of effects held.
    pub fn len(&self) -> usize {
        self.len
    }

    /// Whether no effects are held.
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// Capacity, i.e. `K`.
    pub const fn capacity(&self) -> usize {
        K
    }

    /// Borrow the effects in emission order.
    pub fn iter(&self) -> impl Iterator<Item = &F> {
        self.items[..self.len].iter().filter_map(Option::as_ref)
    }

    /// Relabel every effect. Used by the `translate` composition operator and
    /// by `DELEGATE` cells lifting a child's effects into the parent's.
    pub fn map<G, H: FnMut(F) -> G>(self, mut h: H) -> Effects<G, K> {
        let mut out = Effects::<G, K>::none();
        for f in self {
            out.push(h(f));
        }
        out
    }
}

impl<F, const K: usize> Default for Effects<F, K> {
    fn default() -> Self {
        Self::none()
    }
}

impl<F: fmt::Debug, const K: usize> fmt::Debug for Effects<F, K> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_list().entries(self.iter()).finish()
    }
}

impl<F, const K: usize> IntoIterator for Effects<F, K> {
    type Item = F;
    type IntoIter = core::iter::Flatten<core::array::IntoIter<Option<F>, K>>;
    fn into_iter(self) -> Self::IntoIter {
        self.items.into_iter().flatten()
    }
}

/// The result of dispatching one `(state, action)` pair.
#[derive(Clone, PartialEq, Eq)]
pub struct Step<S, F, const K: usize = DEFAULT_EFFECT_CAPACITY> {
    /// What the cell decided.
    pub outcome: Outcome<S>,
    /// What should be done about it.
    pub effects: Effects<F, K>,
}

impl<S, F, const K: usize> Step<S, F, K> {
    /// Transition to `next`, emitting nothing. Chain [`Step::emit`] to add
    /// effects.
    pub fn go(next: S) -> Self {
        Self {
            outcome: Outcome::Go(next),
            effects: Effects::none(),
        }
    }

    /// Handled; remain in the current state.
    pub fn stay() -> Self {
        Self {
            outcome: Outcome::Stay,
            effects: Effects::none(),
        }
    }

    /// This action is not applicable in this state.
    pub fn ignored() -> Self {
        Self {
            outcome: Outcome::Ignored,
            effects: Effects::none(),
        }
    }

    /// Append an effect.
    ///
    /// ```
    /// # use tabular_center::Step;
    /// # #[derive(Debug, PartialEq)] enum S { Idle }
    /// # #[derive(Debug, PartialEq)] enum F { Stop }
    /// let step: Step<S, F> = Step::go(S::Idle).emit(F::Stop);
    /// assert_eq!(step.effects.len(), 1);
    /// ```
    pub fn emit(mut self, effect: F) -> Self {
        self.effects.push(effect);
        self
    }

    /// Whether the cell declared the action inapplicable.
    pub fn is_ignored(&self) -> bool {
        matches!(self.outcome, Outcome::Ignored)
    }

    /// Whether the cell transitioned.
    pub fn is_transition(&self) -> bool {
        matches!(self.outcome, Outcome::Go(_))
    }

    /// Relabel the target state, keeping effects. Composition primitive.
    pub fn map_state<T, G: FnOnce(S) -> T>(self, g: G) -> Step<T, F, K> {
        Step {
            outcome: self.outcome.map(g),
            effects: self.effects,
        }
    }

    /// Relabel the effects, keeping the outcome. Composition primitive: a
    /// `DELEGATE` cell lifts a child's effects into the parent's vocabulary
    /// with this.
    pub fn map_effect<G, H: FnMut(F) -> G>(self, h: H) -> Step<S, G, K> {
        Step {
            outcome: self.outcome,
            effects: self.effects.map(h),
        }
    }
}

/// A `Step` is a value already decided, so awaiting it yields it at once.
///
/// This is what lets an async parent delegate to a child of either color with
/// one `.await`: a plain child's `step` returns a `Step`, ready immediately;
/// an async child's returns a future, awaited for real. The parent's
/// expansion cannot see which color the child has, and with this it does not
/// need to. A plain parent writes no `.await`, so an async child's future
/// lands where a `Step` is required, which rustc refuses -- one-way color
/// flow, by construction.
impl<S, F, const K: usize> core::future::IntoFuture for Step<S, F, K> {
    type Output = Self;
    type IntoFuture = core::future::Ready<Self>;

    fn into_future(self) -> Self::IntoFuture {
        core::future::ready(self)
    }
}

impl<S: fmt::Debug, F: fmt::Debug, const K: usize> fmt::Debug for Step<S, F, K> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Step")
            .field("outcome", &self.outcome)
            .field("effects", &self.effects)
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    extern crate std;
    use std::vec::Vec;

    #[derive(Debug, PartialEq, Eq, Clone, Copy)]
    enum S {
        A,
        B,
    }
    #[derive(Debug, PartialEq, Eq, Clone, Copy)]
    enum F {
        X,
        Y,
    }

    #[test]
    fn go_carries_target() {
        let s: Step<S, F> = Step::go(S::B);
        assert_eq!(s.outcome, Outcome::Go(S::B));
        assert!(s.effects.is_empty());
        assert!(s.is_transition());
    }

    #[test]
    fn stay_and_ignored_are_distinguishable() {
        let stay: Step<S, F> = Step::stay();
        let ignored: Step<S, F> = Step::ignored();
        assert_ne!(stay.outcome, ignored.outcome);
        assert!(ignored.is_ignored());
        assert!(!stay.is_ignored());
    }

    #[test]
    fn emit_chains_in_order() {
        let s: Step<S, F> = Step::stay().emit(F::X).emit(F::Y);
        let got: Vec<F> = s.effects.iter().copied().collect();
        assert_eq!(got, [F::X, F::Y]);
    }

    #[test]
    fn try_push_returns_the_effect_it_could_not_fit() {
        let mut e: Effects<F, 1> = Effects::none();
        assert!(e.try_push(F::X).is_ok());
        let err = e.try_push(F::Y).unwrap_err();
        assert_eq!(err.rejected, F::Y);
        assert_eq!(err.capacity, 1);
    }

    #[test]
    #[should_panic(expected = "effect capacity 1 exceeded")]
    fn push_beyond_capacity_panics_with_the_remedy() {
        let mut e: Effects<F, 1> = Effects::none();
        e.push(F::X);
        e.push(F::Y);
    }

    #[test]
    fn map_state_relabels_only_the_target() {
        let s: Step<S, F> = Step::go(S::A).emit(F::X);
        let t: Step<u8, F> = s.map_state(|_| 7u8);
        assert_eq!(t.outcome, Outcome::Go(7));
        assert_eq!(t.effects.len(), 1);
    }

    #[test]
    fn map_effect_lifts_into_another_vocabulary() {
        let s: Step<S, F> = Step::stay().emit(F::X).emit(F::Y);
        let t: Step<S, u8> = s.map_effect(|f| match f {
            F::X => 1,
            F::Y => 2,
        });
        let got: Vec<u8> = t.effects.iter().copied().collect();
        assert_eq!(got, [1, 2]);
    }
}
