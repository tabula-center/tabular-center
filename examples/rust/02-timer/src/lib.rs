//! **2. Payloads and effects.**
//!
//! Payloads on both a state and an action, which is what makes narrowed cell
//! arguments worth having: `running_tick` receives `Running` and `Tick` as
//! concrete types, so `state.since` and `action.now` are plain fields rather
//! than something to unwrap.
//!
//! The effect carries a payload too, so the handler is narrowed the same way.

use tabula::{Handle, Perform, Step};

#[derive(Debug, Default)]
pub struct Ctx {
    /// How long a run may last before the timer finishes itself.
    pub limit: u64,
    pub log: Vec<String>,
}

// The matrix lives in `machine.tb.rs`, per `spec/matrix-files.md`.
#[path = "machine.tb.rs"]
mod machine;

pub use machine::*;

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
