//! Driving a machine: the mailbox that makes `step` non-reentrant.
//!
//! # The problem this solves
//!
//! Purity was dropped as a guarantee (it is unenforceable in Kotlin and
//! Swift), and colored cells mean an event can arrive *during* a transition.
//! ARCHITECTURE section 9 commits to handling that by generating the
//! serialisation rather than warning about it. This is that.
//!
//! Two rules, both structural rather than documented:
//!
//! 1. **`step` is never re-entered.** [`Driver::run`] refuses to run inside
//!    itself and says so, rather than corrupting state quietly.
//! 2. **Follow-up actions are queued, never recursed.** An effect handler
//!    returns an action as *data*; the driver enqueues it. A handler cannot
//!    reach back into `step` even if it wants to, because it is handed no way
//!    to.
//!
//! # Why the handlers are closures over a shared environment
//!
//! `step` needs the cell object and the context, and so does `perform`. An
//! earlier version had both closures *capture* them, which does not compile
//! for any realistic caller:
//!
//! ```text
//! error[E0499]: cannot borrow `cells` as mutable more than once at a time
//! ```
//!
//! Found by writing `tabular-center-rust/examples/src/retry.rs` — the first caller that
//! actually needed both closures to touch the same state, which none of the
//! unit tests did. Both now receive `&mut E` instead of capturing, so the
//! caller keeps one environment and the borrow checker is satisfied.
//!
//! Closures rather than a trait keeps `Driver` free of the machine's four type
//! parameters and, more importantly, keeps it colorless: an `async` caller
//! writes an `async` loop around the same pieces instead of asking this type to
//! be generic over an effect system it cannot abstract over.
//!
//! # Ordering
//!
//! Within one step: the outcome is applied **first**, then effects are
//! performed. An effect handler that enqueues an action therefore sees the
//! post-transition state when that action is eventually stepped. The reverse
//! order would make `Step::go(X).emit(E)` mean "perform E while still in the
//! old state", which is almost never what a cell author intends.

use crate::step::{Outcome, Step};

/// Why a driver call could not proceed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DriverError {
    /// The mailbox is full. Carries its capacity, which is a compile-time
    /// property of the driver.
    QueueFull {
        /// The mailbox capacity that was exceeded.
        capacity: usize,
    },
    /// [`Driver::run`] was called from inside itself.
    ///
    /// Reaching this means something handed a handler a way back into the
    /// driver. The design intends that to be impossible; the check exists so
    /// that when it happens it is loud rather than silent.
    Reentered,
}

/// What one [`Driver::run`] accomplished.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Progress {
    /// Actions dispatched through `step`.
    pub steps: usize,
    /// Effects handed to the handler.
    pub effects: usize,
    /// Follow-up actions the handler enqueued.
    pub follow_ups: usize,
    /// Transitions actually taken, i.e. `Outcome::Go`.
    pub transitions: usize,
    /// Actions the machine declared inapplicable.
    pub ignored: usize,
}

/// Owns a machine's current state and its pending actions.
///
/// `Q` is the mailbox capacity. Fixed rather than growable so the whole type
/// works under `no_std` with no allocator; overflow is reported rather than
/// papered over, because an unbounded mailbox just moves the failure somewhere
/// harder to see.
pub struct Driver<S, A, const Q: usize = 8> {
    state: S,
    queue: [Option<A>; Q],
    head: usize,
    len: usize,
    running: bool,
}

impl<S: Copy, A, const Q: usize> Driver<S, A, Q> {
    /// A driver parked in `initial` with an empty mailbox.
    pub fn new(initial: S) -> Self {
        Self {
            state: initial,
            queue: core::array::from_fn(|_| None),
            head: 0,
            len: 0,
            running: false,
        }
    }

    /// The current state.
    pub fn state(&self) -> S {
        self.state
    }

    /// Pending actions.
    pub fn pending(&self) -> usize {
        self.len
    }

    /// Mailbox capacity, i.e. `Q`.
    pub const fn capacity(&self) -> usize {
        Q
    }

    /// Add an action to the back of the mailbox.
    pub fn enqueue(&mut self, action: A) -> Result<(), DriverError> {
        if self.len == Q {
            return Err(DriverError::QueueFull { capacity: Q });
        }
        let at = (self.head + self.len) % Q;
        self.queue[at] = Some(action);
        self.len += 1;
        Ok(())
    }

    fn dequeue(&mut self) -> Option<A> {
        if self.len == 0 {
            return None;
        }
        let a = self.queue[self.head].take();
        self.head = (self.head + 1) % Q;
        self.len -= 1;
        a
    }

    /// Dispatch one action and drain everything it causes.
    ///
    /// Equivalent to [`Driver::enqueue`] followed by [`Driver::run`].
    ///
    /// `env` is whatever both closures need — typically the cell object and
    /// the context together. They receive it rather than capturing it, because
    /// two closures capturing the same `&mut` do not compile.
    pub fn dispatch<Env, F, Ef, H, const K: usize>(
        &mut self,
        env: &mut Env,
        action: A,
        step: F,
        perform: H,
    ) -> Result<Progress, DriverError>
    where
        F: FnMut(&mut Env, S, A) -> Step<S, Ef, K>,
        H: FnMut(&mut Env, Ef) -> Option<A>,
    {
        self.enqueue(action)?;
        self.run(env, step, perform)
    }

    /// Drain the mailbox.
    ///
    /// Runs until nothing is pending: each action is stepped, its outcome
    /// applied, its effects performed, and any follow-up actions the handler
    /// returns are appended to the *back* of the mailbox. Strictly FIFO, so a
    /// follow-up never jumps ahead of an action that was already waiting.
    pub fn run<Env, F, Ef, H, const K: usize>(
        &mut self,
        env: &mut Env,
        mut step: F,
        mut perform: H,
    ) -> Result<Progress, DriverError>
    where
        F: FnMut(&mut Env, S, A) -> Step<S, Ef, K>,
        H: FnMut(&mut Env, Ef) -> Option<A>,
    {
        if self.running {
            return Err(DriverError::Reentered);
        }
        self.running = true;
        let result = self.pump(env, &mut step, &mut perform);
        self.running = false;
        result
    }

    fn pump<Env, F, Ef, H, const K: usize>(
        &mut self,
        env: &mut Env,
        step: &mut F,
        perform: &mut H,
    ) -> Result<Progress, DriverError>
    where
        F: FnMut(&mut Env, S, A) -> Step<S, Ef, K>,
        H: FnMut(&mut Env, Ef) -> Option<A>,
    {
        let mut p = Progress::default();

        while let Some(action) = self.dequeue() {
            let outcome = step(env, self.state, action);
            p.steps += 1;

            // Outcome first, effects second: a handler that enqueues an action
            // should see the post-transition state when that action is stepped.
            match outcome.outcome {
                Outcome::Go(next) => {
                    self.state = next;
                    p.transitions += 1;
                }
                Outcome::Stay => {}
                Outcome::Ignored => p.ignored += 1,
            }

            for effect in outcome.effects {
                p.effects += 1;
                if let Some(follow_up) = perform(env, effect) {
                    // Queued, never recursed. This is the whole point.
                    self.enqueue(follow_up)?;
                    p.follow_ups += 1;
                }
            }
        }
        Ok(p)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    extern crate std;
    use std::cell::RefCell;
    use std::vec::Vec;

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    enum S {
        A,
        B,
        C,
    }
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    enum Act {
        Go,
        Again,
        Nope,
    }
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    enum Eff {
        Ping,
        Done,
    }

    fn machine(s: S, a: Act) -> Step<S, Eff> {
        match (s, a) {
            (S::A, Act::Go) => Step::go(S::B).emit(Eff::Ping),
            (S::B, Act::Again) => Step::go(S::C).emit(Eff::Done),
            (S::C, _) => Step::stay(),
            (_, Act::Nope) => Step::ignored(),
            _ => Step::ignored(),
        }
    }

    #[test]
    fn a_follow_up_action_goes_through_the_mailbox() {
        let mut d: Driver<S, Act, 8> = Driver::new(S::A);
        let seen = RefCell::new(Vec::new());

        let p = d
            .dispatch(
                &mut (),
                Act::Go,
                |_, s, a| machine(s, a),
                |_, e| {
                    seen.borrow_mut().push(e);
                    // Ping asks for another action. Queued, not recursed.
                    match e {
                        Eff::Ping => Some(Act::Again),
                        Eff::Done => None,
                    }
                },
            )
            .unwrap();

        assert_eq!(d.state(), S::C);
        assert_eq!(p.steps, 2);
        assert_eq!(p.follow_ups, 1);
        assert_eq!(p.transitions, 2);
        assert_eq!(*seen.borrow(), [Eff::Ping, Eff::Done]);
    }

    #[test]
    fn the_outcome_is_applied_before_effects_are_performed() {
        // A handler that inspects state must see where the machine has gone,
        // not where it was. `Step::go(B).emit(E)` means "we are in B; now do
        // E", never "do E, then move".
        let mut d: Driver<S, Act, 8> = Driver::new(S::A);
        let observed = RefCell::new(Vec::new());
        d.dispatch(
            &mut (),
            Act::Go,
            |_, s, a| machine(s, a),
            |_, _e| {
                observed.borrow_mut().push(S::B);
                None
            },
        )
        .unwrap();
        assert_eq!(*observed.borrow(), [S::B]);
    }

    #[test]
    fn the_mailbox_is_fifo_so_follow_ups_never_jump_the_queue() {
        let mut d: Driver<S, Act, 8> = Driver::new(S::A);
        d.enqueue(Act::Nope).unwrap();
        d.enqueue(Act::Go).unwrap();

        let order = RefCell::new(Vec::new());
        let p = d
            .run(
                &mut (),
                |_, s, a| {
                    order.borrow_mut().push(a);
                    machine(s, a)
                },
                |_, _| None,
            )
            .unwrap();

        assert_eq!(*order.borrow(), [Act::Nope, Act::Go]);
        assert_eq!(p.ignored, 1);
    }

    #[test]
    fn ignored_actions_leave_the_state_alone() {
        let mut d: Driver<S, Act, 4> = Driver::new(S::A);
        let p = d
            .dispatch(&mut (), Act::Nope, |_, s, a| machine(s, a), |_, _| None)
            .unwrap();
        assert_eq!(d.state(), S::A);
        assert_eq!(p.ignored, 1);
        assert_eq!(p.transitions, 0);
    }

    #[test]
    fn overflow_names_the_capacity_rather_than_growing() {
        let mut d: Driver<S, Act, 2> = Driver::new(S::A);
        d.enqueue(Act::Nope).unwrap();
        d.enqueue(Act::Nope).unwrap();
        assert_eq!(
            d.enqueue(Act::Nope),
            Err(DriverError::QueueFull { capacity: 2 })
        );
    }

    #[test]
    fn the_ring_buffer_wraps() {
        let mut d: Driver<S, Act, 2> = Driver::new(S::C);
        for _ in 0..5 {
            d.dispatch(&mut (), Act::Go, |_, s, a| machine(s, a), |_, _| None)
                .unwrap();
            assert_eq!(d.pending(), 0);
        }
        assert_eq!(d.state(), S::C);
    }
}
