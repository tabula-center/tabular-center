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
            "tabular-center: effect capacity {} exceeded; raise K on Step<S, F, K>",
            self.capacity
        )
    }
}

/// Why [`Step::try_emit`] refused an effect, handing it back: the step is
/// ignored, and an ignored step emits nothing (spec/cells.md 2.1), or the
/// effects are at capacity.
pub enum EmitError<F> {
    /// The step is `Ignored`.
    Ignored(F),
    /// The step already holds `K` effects.
    Capacity(CapacityError<F>),
}

impl<F> fmt::Debug for EmitError<F> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EmitError::Ignored(_) => write!(f, "EmitError::Ignored"),
            EmitError::Capacity(e) => write!(f, "EmitError::Capacity({e:?})"),
        }
    }
}

const IGNORED_EMITS_NOTHING: &str =
    "tabular-center: an ignored step emits nothing (spec/cells.md 2.1); emit on Step::stay()";

impl<F> fmt::Display for EmitError<F> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EmitError::Ignored(_) => f.write_str(IGNORED_EMITS_NOTHING),
            EmitError::Capacity(e) => write!(f, "{e}"),
        }
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
            panic!("tabular-center: effect capacity {K} exceeded; raise K on Step<S, F, K>");
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

/// The result of dispatching one `(state, action)` pair: an [`Outcome`] and
/// the effects the cell emitted, in order.
///
/// A step is a value, and it composes (spec/cells.md 6):
///
/// - `map(f)` applies `f` to a `Go` target; `Stay` and `Ignored` pass through.
/// - `and_then(f)` runs `f` on a `Go` target and returns `f`'s outcome, with
///   this step's effects followed by `f`'s. `Stay` and `Ignored` short-circuit
///   without calling `f`. An `Ignored` from `f` absorbs: the result is
///   `Ignored` with no effects.
/// - `zip_with(other, g)` is `and_then(|x| other.map(|y| g(x, y)))`, and
///   `zip(other)` pairs the targets. When this step is not `Go`, `other`'s
///   effects are dropped.
///
/// ```
/// # use tabular_center::{Outcome, Step};
/// # #[derive(Debug, PartialEq)] enum S { Validating, Ready }
/// # #[derive(Debug, PartialEq)] enum F { Log, Fetch }
/// fn enter(s: S) -> Step<S, F> {
///     match s {
///         S::Validating => Step::go(S::Validating).emit(F::Fetch),
///         other => Step::go(other),
///     }
/// }
/// let step: Step<S, F> = Step::go(S::Validating).emit(F::Log).and_then(enter);
/// assert_eq!(step.outcome, Outcome::Go(S::Validating));
/// assert_eq!(step.effects.iter().collect::<Vec<_>>(), [&F::Log, &F::Fetch]);
/// # let _ = S::Ready;
/// ```
///
/// Effects concatenate into the same capacity `K`, so `emit`, `and_then` and
/// `zip_with` panic past it, as [`Effects::push`] does; `try_emit` and
/// `try_and_then` return the error instead. `emit` on an `Ignored` step
/// panics too: an ignored step emits nothing.
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
        if let Err(e) = self.try_emit(effect) {
            panic!("{e}");
        }
        self
    }

    pub fn try_emit(&mut self, effect: F) -> Result<(), EmitError<F>> {
        if let Outcome::Ignored = self.outcome {
            return Err(EmitError::Ignored(effect));
        }
        self.effects.try_push(effect).map_err(EmitError::Capacity)
    }

    /// Whether the cell declared the action inapplicable.
    pub fn is_ignored(&self) -> bool {
        matches!(self.outcome, Outcome::Ignored)
    }

    /// Whether the cell transitioned.
    pub fn is_transition(&self) -> bool {
        matches!(self.outcome, Outcome::Go(_))
    }

    pub fn map<T, G: FnOnce(S) -> T>(self, g: G) -> Step<T, F, K> {
        Step {
            outcome: self.outcome.map(g),
            effects: self.effects,
        }
    }

    #[deprecated(note = "use `Step::map`")]
    pub fn map_state<T, G: FnOnce(S) -> T>(self, g: G) -> Step<T, F, K> {
        self.map(g)
    }

    pub fn and_then<T, G: FnOnce(S) -> Step<T, F, K>>(self, g: G) -> Step<T, F, K> {
        match self.try_and_then(g) {
            Ok(step) => step,
            Err(e) => panic!("{e}"),
        }
    }

    pub fn try_and_then<T, G: FnOnce(S) -> Step<T, F, K>>(
        self,
        g: G,
    ) -> Result<Step<T, F, K>, CapacityError<F>> {
        let outcome = self.outcome;
        let mut effects = self.effects;
        let target = match outcome {
            Outcome::Go(target) => target,
            Outcome::Stay => return Ok(Step::from_parts(Outcome::Stay, effects)),
            Outcome::Ignored => return Ok(Step::ignored()),
        };
        let next = g(target);
        if let Outcome::Ignored = next.outcome {
            return Ok(Step::ignored());
        }
        for effect in next.effects {
            effects.try_push(effect)?;
        }
        Ok(Step::from_parts(next.outcome, effects))
    }

    fn from_parts(outcome: Outcome<S>, effects: Effects<F, K>) -> Self {
        Self { outcome, effects }
    }

    pub fn zip_with<T, U, H: FnOnce(S, T) -> U>(self, other: Step<T, F, K>, h: H) -> Step<U, F, K> {
        self.and_then(|x| other.map(|y| h(x, y)))
    }

    pub fn zip<T>(self, other: Step<T, F, K>) -> Step<(S, T), F, K> {
        self.zip_with(other, |x, y| (x, y))
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
    fn map_relabels_only_the_target() {
        let s: Step<S, F> = Step::go(S::A).emit(F::X);
        let t: Step<u8, F> = s.map(|_| 7u8);
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
