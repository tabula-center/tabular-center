//! **2. Payloads and effects.**
//!
//! Payloads on both a state and an action, which is what makes narrowed cell
//! arguments worth having: `running_tick` receives `Running` and `Tick` as
//! concrete types, so `state.since` and `action.now` are plain fields rather
//! than something to unwrap.
//!
//! The effect carries a payload too, so the handler is narrowed the same way.

use tabula::{transition_matrix, Handle, Perform, Step};

#[derive(Debug, Default)]
pub struct Ctx {
    /// How long a run may last before the timer finishes itself.
    pub limit: u64,
    pub log: Vec<String>,
}

transition_matrix! {
    machine Timer;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { StartClock, StopClock { reason: Reason } }
    initial Idle;

    states  { Idle, Running { since: u64 }, Done }
    actions { Start, Tick { now: u64 }, Cancel }

    //            Start                                  Tick     Cancel
    Idle    => [  HANDLE,                                IGNORE,  IGNORE                                  ];
    Running => [  IGNORE,                                HANDLE,  GO!(Idle, StopClock { reason: Reason::Cancelled }) ];
    Done    => [  GO!(Running { since: 0 }, StartClock), IGNORE,  IGNORE                                  ];
}

/// Why a clock stopped. A payload with meaning, rather than a bare flag —
/// `StopClock` is emitted from two very different places.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reason {
    Cancelled,
    Elapsed,
}

#[derive(Default)]
pub struct Impl;

impl Handle<Timer, Idle, Start> for Impl {
    fn handle(&mut self, _c: &mut Ctx, _s: Idle, _a: Start) -> Step<State, Effect> {
        Step::go(State::Running(Running { since: 0 })).emit(StartClock.into())
    }
}

impl Handle<Timer, Running, Tick> for Impl {
    fn handle(&mut self, c: &mut Ctx, s: Running, a: Tick) -> Step<State, Effect> {
        // No `if let`, no cast, no unwrap: the dispatcher already matched.
        if a.now.saturating_sub(s.since) >= c.limit {
            Step::go(State::Done(Done)).emit(
                StopClock {
                    reason: Reason::Elapsed,
                }
                .into(),
            )
        } else {
            // Handled, and staying put. Distinct from `Ignored`, which would
            // claim a tick is meaningless while running.
            Step::stay()
        }
    }
}

impl Perform<Timer, StartClock> for Impl {
    fn perform(&mut self, c: &mut Ctx, _e: StartClock) -> Option<Action> {
        c.log.push("start".into());
        None
    }
}

impl Perform<Timer, StopClock> for Impl {
    fn perform(&mut self, c: &mut Ctx, e: StopClock) -> Option<Action> {
        c.log.push(format!("stop:{:?}", e.reason));
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tabula::Outcome;

    fn ctx(limit: u64) -> Ctx {
        Ctx {
            limit,
            ..Default::default()
        }
    }

    #[test]
    fn a_tick_below_the_limit_stays_and_is_not_ignored() {
        let mut c = ctx(10);
        let s = step(
            &mut Impl,
            &mut c,
            State::Running(Running { since: 0 }),
            Action::Tick(Tick { now: 1 }),
        );
        assert_eq!(s.outcome, Outcome::Stay);
        assert!(!s.is_ignored(), "a tick while running is meaningful");
    }

    #[test]
    fn the_limit_finishes_the_timer() {
        let mut c = ctx(3);
        let s = step(
            &mut Impl,
            &mut c,
            State::Running(Running { since: 2 }),
            Action::Tick(Tick { now: 9 }),
        );
        assert_eq!(s.outcome, Outcome::Go(State::Done(Done)));
        assert_eq!(
            s.effects.iter().copied().collect::<Vec<_>>(),
            [Effect::StopClock(StopClock {
                reason: Reason::Elapsed
            })]
        );
    }

    #[test]
    fn the_same_effect_carries_different_reasons() {
        // Cancelling and elapsing both stop the clock; the payload is what
        // tells a handler which happened.
        let mut c = ctx(100);
        let cancelled = step(
            &mut Impl,
            &mut c,
            State::Running(Running { since: 0 }),
            Action::Cancel(Cancel),
        );
        assert_eq!(
            cancelled.effects.iter().copied().collect::<Vec<_>>(),
            [Effect::StopClock(StopClock {
                reason: Reason::Cancelled
            })]
        );
    }

    #[test]
    fn effect_handlers_receive_narrowed_payloads() {
        let mut c = ctx(1);
        perform(
            &mut Impl,
            &mut c,
            StopClock {
                reason: Reason::Elapsed,
            }
            .into(),
        );
        assert_eq!(c.log, ["stop:Elapsed"]);
    }

    #[test]
    fn actions_that_mean_nothing_here_are_ignored() {
        let mut c = ctx(1);
        for (st, ac) in [
            (State::Idle(Idle), Action::Tick(Tick { now: 1 })),
            (State::Idle(Idle), Action::Cancel(Cancel)),
            (State::Done(Done), Action::Cancel(Cancel)),
        ] {
            assert!(step(&mut Impl, &mut c, st, ac).is_ignored());
        }
    }
}
