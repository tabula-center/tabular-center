//! Composition: a parent machine driving a child through a `DELEGATE` cell.
//!
//! The claim under test:
//!
//! > Scoping a total child into a total parent yields a total parent, and the
//! > compiler proves it by the same mechanism as everything else.
//!
//! `DELEGATE` differs from `HANDLE` in exactly one way that matters: the
//! generated cell calls the child's `step`, so the parent's bound set includes
//! `child::Cells` — the child's entire cell surface. A hole anywhere in the
//! child breaks the *parent's* build. A hand-written `HANDLE` body could never
//! give that, because it is free to ignore the child.

use tabula::{transition_matrix, Handle, Outcome, Step};

// ---------------------------------------------------------------------------
// Child: a retry machine, written without knowing anything about its parent.
// ---------------------------------------------------------------------------

mod retry {
    use super::*;

    #[derive(Debug, Default)]
    pub struct Ctx {
        pub max_attempts: u32,
    }

    transition_matrix! {
        machine Retry;
        context Ctx;
        state   State;
        action  Action;
        effects Effect { Sleep, GiveUp }
        initial Ready;

        states  { Ready, Waiting { attempt: u32 }, Exhausted }
        actions { Attempt, Elapsed, Abort }

        //              Attempt   Elapsed   Abort
        Ready     => [  HANDLE,   IGNORE,   GO!(Exhausted)  ];
        Waiting   => [  IGNORE,   HANDLE,   GO!(Exhausted)  ];
        Exhausted => [  IGNORE,   IGNORE,   IGNORE          ];
    }
}

// ---------------------------------------------------------------------------
// Parent: a job machine whose `Retrying` state holds the child's state.
// ---------------------------------------------------------------------------

mod job {
    use super::*;

    /// The parent's context **contains** the child's.
    ///
    /// This is the whole answer to context plumbing: `child_ctx` is then a
    /// field access, and the child never sees parent state it has no business
    /// with. Rule R4 applied one level up.
    #[derive(Debug, Default)]
    pub struct Ctx {
        pub attempts_made: u32,
        pub retry: super::retry::Ctx,
    }

    transition_matrix! {
        machine Job;
        context Ctx;
        state   State;
        action  Action;
        effects Effect { Log, Backoff, Alert }
        initial Idle;

        states  { Idle, Retrying { child: retry::State }, Done }
        actions { Run, Tick, Cancel }

        //              Run                 Tick                 Cancel
        Idle      => [  HANDLE,             IGNORE,              IGNORE             ];
        Retrying  => [  DELEGATE!(retry),   DELEGATE!(retry),    GO!(Done, Log) ];
        Done      => [  IGNORE,             IGNORE,              IGNORE             ];
    }
}

use job::{Action, Cancel, Idle, Retrying, Run, State, Tick};

// ---------------------------------------------------------------------------
// The developer's side
// ---------------------------------------------------------------------------

#[derive(Default)]
struct Impl;

// The parent's own HANDLE cell.
impl Handle<job::Job, Idle, Run> for Impl {
    fn handle(&mut self, _c: &mut job::Ctx, _s: Idle, _a: Run) -> Step<State, job::Effect> {
        Step::go(State::Retrying(Retrying {
            child: retry::State::Ready(retry::Ready),
        }))
        .emit(job::Log.into())
    }
}

// The child's HANDLE cells. Note these are implemented on the *same* type:
// one object satisfies both machines' surfaces, which is what lets the parent
// pass `self` straight through to `retry::step`.
impl Handle<retry::Retry, retry::Ready, retry::Attempt> for Impl {
    fn handle(
        &mut self,
        _c: &mut retry::Ctx,
        _s: retry::Ready,
        _a: retry::Attempt,
    ) -> Step<retry::State, retry::Effect> {
        Step::go(retry::State::Waiting(retry::Waiting { attempt: 1 })).emit(retry::Sleep.into())
    }
}

impl Handle<retry::Retry, retry::Waiting, retry::Elapsed> for Impl {
    fn handle(
        &mut self,
        c: &mut retry::Ctx,
        s: retry::Waiting,
        _a: retry::Elapsed,
    ) -> Step<retry::State, retry::Effect> {
        if s.attempt >= c.max_attempts {
            Step::go(retry::State::Exhausted(retry::Exhausted)).emit(retry::GiveUp.into())
        } else {
            Step::go(retry::State::Waiting(retry::Waiting {
                attempt: s.attempt + 1,
            }))
            .emit(retry::Sleep.into())
        }
    }
}

// The lens: written ONCE for (Retrying, retry), however many cells delegate.
//
// An earlier version had all five methods on `Delegate`, instantiated per
// cell, so these four were duplicated verbatim below. The Kotlin
// implementation made the duplication obvious, and the finding came back here.
impl tabula::Lens<job::Job, Retrying, retry::Marker> for Impl {
    fn child_state(&mut self, s: &Retrying) -> retry::State {
        s.child
    }

    fn embed(&mut self, _s: Retrying, child: retry::State) -> State {
        lift_child(child)
    }

    fn lift(&mut self, e: retry::Effect) -> job::Effect {
        lift_effect(e)
    }

    fn child_ctx<'a>(&mut self, ctx: &'a mut job::Ctx) -> &'a mut retry::Ctx {
        ctx.attempts_made += 1;
        &mut ctx.retry
    }
}

// The prisms: one per delegate cell, and the only genuinely per-cell part.
impl tabula::Delegate<job::Job, Retrying, Run, retry::Marker> for Impl {
    fn to_child(&mut self, _ctx: &mut job::Ctx, _s: &Retrying, _a: Run) -> Option<retry::Action> {
        Some(retry::Action::Attempt(retry::Attempt))
    }
}

impl tabula::Delegate<job::Job, Retrying, Tick, retry::Marker> for Impl {
    fn to_child(&mut self, _ctx: &mut job::Ctx, _s: &Retrying, _a: Tick) -> Option<retry::Action> {
        Some(retry::Action::Elapsed(retry::Elapsed))
    }
}

/// The child reaching `Exhausted` is the parent's cue to leave `Retrying`.
///
/// This is why `embed` returns the full parent state rather than the narrowed
/// variant: a child transition often *is* a parent transition.
fn lift_child(child: retry::State) -> State {
    match child {
        retry::State::Exhausted(_) => State::Done(job::Done),
        other => State::Retrying(Retrying { child: other }),
    }
}

fn lift_effect(e: retry::Effect) -> job::Effect {
    match e {
        retry::Effect::Sleep(_) => job::Effect::Backoff(job::Backoff),
        retry::Effect::GiveUp(_) => job::Effect::Alert(job::Alert),
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn ctx(max: u32) -> job::Ctx {
    job::Ctx {
        attempts_made: 0,
        retry: retry::Ctx { max_attempts: max },
    }
}

#[test]
fn delegate_runs_the_child_and_lifts_its_effects() {
    let (mut m, mut c) = (Impl, ctx(3));
    let s = job::step(
        &mut m,
        &mut c,
        State::Retrying(Retrying {
            child: retry::State::Ready(retry::Ready),
        }),
        Action::Run(Run),
    );
    // Child went Ready -> Waiting, emitting Sleep; the parent sees Backoff.
    assert_eq!(
        s.outcome,
        Outcome::Go(State::Retrying(Retrying {
            child: retry::State::Waiting(retry::Waiting { attempt: 1 })
        }))
    );
    assert_eq!(
        s.effects.iter().copied().collect::<Vec<_>>(),
        [job::Effect::Backoff(job::Backoff)]
    );
    assert_eq!(c.attempts_made, 1);
}

#[test]
fn a_child_transition_can_be_a_parent_transition() {
    // `embed` returns the full parent state, so the child reaching Exhausted
    // moves the parent out of Retrying entirely.
    let (mut m, mut c) = (Impl, ctx(1));
    let s = job::step(
        &mut m,
        &mut c,
        State::Retrying(Retrying {
            child: retry::State::Waiting(retry::Waiting { attempt: 1 }),
        }),
        Action::Tick(Tick),
    );
    assert_eq!(s.outcome, Outcome::Go(State::Done(job::Done)));
    assert_eq!(
        s.effects.iter().copied().collect::<Vec<_>>(),
        [job::Effect::Alert(job::Alert)]
    );
}

#[test]
fn a_static_parent_cell_beside_a_delegate_still_works() {
    let (mut m, mut c) = (Impl, ctx(3));
    let s = job::step(
        &mut m,
        &mut c,
        State::Retrying(Retrying {
            child: retry::State::Ready(retry::Ready),
        }),
        Action::Cancel(Cancel),
    );
    assert_eq!(s.outcome, Outcome::Go(State::Done(job::Done)));
    assert_eq!(
        s.effects.iter().copied().collect::<Vec<_>>(),
        [job::Effect::Log(job::Log)]
    );
    // The delegate never ran, so the child context was never touched.
    assert_eq!(c.attempts_made, 0);
}

#[test]
fn coverage_is_not_inherited_silently() {
    // The parent's Retrying row still lists all three columns. Two delegate,
    // one does not, and you can see which from the table alone.
    use tabula::Cell;
    assert_eq!(job::TABLE.cell(1, 0), Cell::Delegate { child: "retry" });
    assert_eq!(job::TABLE.cell(1, 1), Cell::Delegate { child: "retry" });
    assert_eq!(job::TABLE.cell(1, 2).static_target(), Some("Done"));

    // Both machines are independently total.
    assert_eq!(job::TABLE.coverage().total(), 9);
    assert_eq!(retry::TABLE.coverage().total(), 9);
    assert_eq!(retry::TABLE.coverage().handle, 2);
}

#[test]
fn the_child_can_be_driven_on_its_own() {
    // Nothing about being a child changed the child. It has its own step,
    // its own table, and no knowledge of the parent.
    let (mut m, mut c) = (Impl, retry::Ctx { max_attempts: 2 });
    let s = retry::step(
        &mut m,
        &mut c,
        retry::State::Ready(retry::Ready),
        retry::Action::Attempt(retry::Attempt),
    );
    assert_eq!(
        s.outcome,
        Outcome::Go(retry::State::Waiting(retry::Waiting { attempt: 1 }))
    );
}

#[cfg(feature = "alloc")]
#[test]
fn delegate_cells_render_as_delegating() {
    let grid = tabula::export::to_grid(&job::TABLE);
    assert!(grid.contains("DELEGATE(retry)"), "{grid}");
}
