//! **3. The driver, and why `step` is non-reentrant.**
//!
//! The only example where an effect handler returns an action. That path is
//! the whole reason the driver exists: the follow-up goes onto the mailbox and
//! is stepped on the next turn of the loop, rather than recursing into `step`
//! from inside a handler.
//!
//! A handler is given no way back into `step`. Re-entrancy is impossible here
//! rather than merely discouraged, which is the distinction the design cares
//! about everywhere else too.

use tabular_center::{Driver, Handle, Perform, Step};

#[derive(Debug, Default)]
pub struct Ctx {
    pub max_attempts: u32,
    pub performed: Vec<String>,
}

#[path = "machine.tb.rs"]
mod machine;

pub use machine::*;

#[derive(Default)]
pub struct Impl;

impl Handle<Retry, Ready, Attempt> for Impl {
    fn handle(&mut self, _c: &mut Ctx, _s: Ready, _a: Attempt) -> Step<State, Effect> {
        Step::go(State::Waiting(Waiting { attempt: 1 })).emit(Sleep { ms: 100 }.into())
    }
}

impl Handle<Retry, Waiting, Elapsed> for Impl {
    fn handle(&mut self, c: &mut Ctx, s: Waiting, _a: Elapsed) -> Step<State, Effect> {
        if s.attempt >= c.max_attempts {
            Step::go(State::Exhausted(Exhausted)).emit(GiveUp.into())
        } else {
            let next = s.attempt + 1;
            Step::go(State::Waiting(Waiting { attempt: next })).emit(
                Sleep {
                    ms: 100 * u64::from(next),
                }
                .into(),
            )
        }
    }
}

impl Perform<Retry, Sleep> for Impl {
    fn perform(&mut self, c: &mut Ctx, e: Sleep) -> Option<Action> {
        c.performed.push(format!("sleep:{}", e.ms));
        Some(Action::Elapsed(Elapsed))
    }
}

impl Perform<Retry, GiveUp> for Impl {
    fn perform(&mut self, c: &mut Ctx, _e: GiveUp) -> Option<Action> {
        c.performed.push("give-up".into());
        None
    }
}

pub fn run(max_attempts: u32) -> (State, Ctx) {
    let mut env = (
        Impl,
        Ctx {
            max_attempts,
            performed: Vec::new(),
        },
    );
    let mut driver: Driver<State, Action, 8> = Driver::new(State::Ready(Ready));

    driver
        .dispatch(
            &mut env,
            Action::Attempt(Attempt),
            |(cells, ctx), s, a| step(cells, ctx, s, a),
            |(cells, ctx), e| perform(cells, ctx, e),
        )
        .expect("the mailbox holds eight; this machine never queues two");

    (driver.state(), env.1)
}
