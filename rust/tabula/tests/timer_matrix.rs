//! The same machine as `reference_timer.rs`, declared as a matrix.
//!
//! The point of this file is parity: the macro must produce behaviour
//! indistinguishable from the hand-written version, and `cargo expand` on it
//! must be reviewable by someone who did not write the macro.

use tabula::{transition_matrix, Handle, Outcome, Perform, Step};

/// Cross-state data. Rule R4.
#[derive(Debug, Default)]
pub struct Ctx {
    pub limit: u32,
    pub ticks_seen: u32,
}

transition_matrix! {
    machine Timer;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { StartClock, StopClock { reason: u32 } }
    initial Idle;

    states  { Idle, Running { since: u32 }, Done }
    actions { Start, Tick { now: u32 }, Cancel }

    //            Start                                          Tick      Cancel
    Idle    => [  HANDLE,                                        IGNORE,   IGNORE                       ];
    Running => [  IGNORE,                                        HANDLE,   GO!(Idle, StopClock { reason: 0 }) ];
    Done    => [  GO!(Running { since: 0 }, StartClock), IGNORE,   IGNORE                       ];
}

// ---------------------------------------------------------------------------
// The developer's side: two impls, because two cells are HANDLE.
// ---------------------------------------------------------------------------

#[derive(Default)]
struct TimerImpl;

impl Handle<Timer, Idle, Start> for TimerImpl {
    fn handle(&mut self, _ctx: &mut Ctx, _state: Idle, _action: Start) -> Step<State, Effect> {
        Step::go(State::Running(Running { since: 0 })).emit(StartClock.into())
    }
}

impl Handle<Timer, Running, Tick> for TimerImpl {
    fn handle(&mut self, ctx: &mut Ctx, state: Running, action: Tick) -> Step<State, Effect> {
        // Narrowed and destructured by the generated dispatcher: `state.since`
        // and `action.now` are plain fields, not `Option`s behind a match.
        ctx.ticks_seen += 1;
        if action.now.saturating_sub(state.since) >= ctx.limit {
            Step::go(State::Done(Done)).emit(StopClock { reason: 1 }.into())
        } else {
            Step::stay()
        }
    }
}

fn ctx(limit: u32) -> Ctx {
    Ctx {
        limit,
        ticks_seen: 0,
    }
}

// ---------------------------------------------------------------------------
// Parity with the hand-written reference
// ---------------------------------------------------------------------------

#[test]
fn handle_cell_dispatches_into_developer_code() {
    let (mut m, mut c) = (TimerImpl, ctx(5));
    let s = step(&mut m, &mut c, State::Idle(Idle), Action::Start(Start));
    assert_eq!(s.outcome, Outcome::Go(State::Running(Running { since: 0 })));
    assert_eq!(
        s.effects.iter().copied().collect::<Vec<_>>(),
        [Effect::StartClock(StartClock)]
    );
}

#[test]
fn static_go_cell_needs_no_developer_code() {
    let (mut m, mut c) = (TimerImpl, ctx(5));
    let s = step(
        &mut m,
        &mut c,
        State::Running(Running { since: 3 }),
        Action::Cancel(Cancel),
    );
    assert_eq!(s.outcome, Outcome::Go(State::Idle(Idle)));
    assert_eq!(
        s.effects.iter().copied().collect::<Vec<_>>(),
        [Effect::StopClock(StopClock { reason: 0 })]
    );
}

#[test]
fn ignore_cells_report_ignored() {
    let (mut m, mut c) = (TimerImpl, ctx(5));
    for (st, ac) in [
        (State::Idle(Idle), Action::Tick(Tick { now: 1 })),
        (State::Idle(Idle), Action::Cancel(Cancel)),
        (State::Running(Running { since: 0 }), Action::Start(Start)),
        (State::Done(Done), Action::Tick(Tick { now: 1 })),
        (State::Done(Done), Action::Cancel(Cancel)),
    ] {
        let s = step(&mut m, &mut c, st, ac);
        assert!(s.is_ignored(), "{st:?} x {ac:?}");
        assert!(s.effects.is_empty());
    }
}

#[test]
fn stay_is_distinct_from_ignored() {
    let (mut m, mut c) = (TimerImpl, ctx(100));
    let s = step(
        &mut m,
        &mut c,
        State::Running(Running { since: 0 }),
        Action::Tick(Tick { now: 1 }),
    );
    assert_eq!(s.outcome, Outcome::Stay);
    assert!(!s.is_ignored());
    assert_eq!(c.ticks_seen, 1);
}

#[test]
fn full_trace_reaches_done() {
    let (mut m, mut c) = (TimerImpl, ctx(3));
    let mut state = State::Idle(Idle);
    let mut log = Vec::new();
    for ac in [
        Action::Start(Start),
        Action::Tick(Tick { now: 1 }),
        Action::Tick(Tick { now: 9 }),
        Action::Cancel(Cancel),
    ] {
        let s = step(&mut m, &mut c, state, ac);
        if let Outcome::Go(next) = s.outcome {
            state = next;
        }
        log.push(state);
    }
    assert_eq!(
        log,
        [
            State::Running(Running { since: 0 }),
            State::Running(Running { since: 0 }),
            State::Done(Done),
            State::Done(Done), // Done x Cancel is IGNORE
        ]
    );
}

// ---------------------------------------------------------------------------
// The generated table
// ---------------------------------------------------------------------------

#[test]
fn table_matches_the_declaration() {
    assert_eq!(TABLE.machine, "Timer");
    assert_eq!(TABLE.states, ["Idle", "Running", "Done"]);
    assert_eq!(TABLE.actions, ["Start", "Tick", "Cancel"]);
    assert_eq!(TABLE.initial, Some("Idle"));

    let c = TABLE.coverage();
    assert_eq!(c.total(), 9);
    assert_eq!(c.handle, 2);
    assert_eq!(c.ignore, 5);
    assert_eq!(c.go, 2);
    // Exactly the two `Handle` impls above.
    assert_eq!(c.required_members(), 2);
}

#[test]
fn go_targets_are_recorded_as_bare_variant_names() {
    // `GO!(Running { since: 0 })` must appear as `Running`, not as the whole
    // struct literal, or diagrams and grids become unreadable.
    assert_eq!(TABLE.cell(2, 0).static_target(), Some("Running"));
    assert_eq!(TABLE.cell(1, 2).static_target(), Some("Idle"));
    assert_eq!(TABLE.cell(1, 2).static_effects(), &["StopClock"]);
}

#[test]
fn narrowed_structs_and_from_impls_exist() {
    let s: State = Running { since: 7 }.into();
    assert_eq!(s, State::Running(Running { since: 7 }));
    let a: Action = Cancel.into();
    assert_eq!(a, Action::Cancel(Cancel));
}

#[cfg(feature = "alloc")]
#[test]
fn table_renders_the_same_grid_as_the_reference() {
    let grid = tabula::export::to_grid(&TABLE);
    assert!(grid.contains("HANDLE"));
    // Effects render as bare variant names now that the generator owns them.
    assert!(grid.contains("GO(Idle, StopClock)"), "{grid}");

    let mermaid = tabula::export::to_mermaid(&TABLE);
    assert!(mermaid.contains("[*] --> Idle"));
    assert!(mermaid.contains("Running --> Idle: Cancel / StopClock"));
    // A HANDLE cell's target is not knowable at build time, so it is a
    // self-loop rather than an invented edge.
    assert!(mermaid.contains("Idle --> Idle: Start / ?handle"));
}
