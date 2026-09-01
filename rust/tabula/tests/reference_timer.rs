//! **The macro's specification.**
//!
//! This file is what `transition_matrix!` must expand to. It is hand-written,
//! kept building forever, and every structural claim in ARCHITECTURE.md is
//! exercised here before the macro exists to make it convenient.
//!
//! Read it as four parts:
//!
//! 1. The domain types the developer writes: `State`, `Action`, `Effect`.
//! 2. The **cell surface** -- one `Handle<Machine, StateVariant, ActionVariant>`
//!    impl per non-static cell, each taking *narrowed* argument types.
//!    (Rust names cells by trait bound rather than by identifier, because
//!    `macro_rules!` cannot concatenate idents. See `src/machine.rs`.)
//! 3. The **dispatcher** -- a `match (state, action)` with **no wildcard arm**.
//! 4. The **table** -- the same matrix as inert data.
//!
//! The matrix being specified:
//!
//! ```text
//!               Start                        Tick        Cancel
//!   Idle    [   HANDLE,                      IGNORE,     IGNORE                  ]
//!   Running [   IGNORE,                      HANDLE,     GO(Idle, StopClock)     ]
//!   Done    [   GO(Running(0), StartClock),  IGNORE,     IGNORE                  ]
//! ```

use tabula::{Cell, Handle, Machine, Outcome, Step, Table};

// ---------------------------------------------------------------------------
// 1. Domain types
// ---------------------------------------------------------------------------

/// Payload-carrying state. Payloads cost nothing here, because coverage comes
/// from member counting rather than from pattern matching -- there is no
/// "strict mode / rich mode" fork in this design.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    Idle,
    Running(u32),
    Done,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    Start,
    Tick { now: u32 },
    Cancel,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Effect {
    StartClock,
    StopClock,
}

/// Cross-state data. Rule R4: payload is state-local, Context outlives
/// transitions.
#[derive(Debug, Default)]
pub struct Ctx {
    pub limit: u32,
    pub ticks_seen: u32,
}

// ---------------------------------------------------------------------------
// 1b. Narrowed variant types
// ---------------------------------------------------------------------------
//
// The generator synthesizes one struct per variant so cell members can take
// concrete, already-destructured arguments. This is the piece that is
// impractical to write by hand at scale, and the strongest argument for
// generating the dispatcher rather than hand-writing a `match`.

/// `State::Running`, narrowed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Running(pub u32);

/// `State::Idle`, narrowed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Idle;

/// `Action::Start`, narrowed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Start;

/// `Action::Tick`, narrowed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Tick {
    pub now: u32,
}

// ---------------------------------------------------------------------------
// 2. Cell surface
// ---------------------------------------------------------------------------

/// Machine marker, tying the four types together so `Handle` needs three
/// parameters rather than six.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Timer;

impl Machine for Timer {
    type State = State;
    type Action = Action;
    type Effect = Effect;
    type Ctx = Ctx;
}

// The cell surface is the `where` clause on `step` below: one
// `Handle<Timer, StateVariant, ActionVariant>` bound per non-static cell.
//
// Static cells (`IGNORE`, `GO`, `EMIT`) appear nowhere: they are resolved in
// the dispatcher. Six of this machine's nine cells are static, which is what
// keeps an N x M matrix survivable.
//
// Drop either impl and this file does not compile, with `the trait bound
// `TimerImpl: Handle<Timer, Idle, Start>` is not satisfied`. That is the
// guarantee, and it comes from rustc, not from tabula.

// ---------------------------------------------------------------------------
// 3. Dispatcher
// ---------------------------------------------------------------------------

/// Dispatch one `(state, action)` pair.
///
/// Note the absence of a wildcard arm. Adding a variant to `State` or `Action`
/// breaks this `match` at compile time via `rustc`'s own exhaustiveness
/// checker -- a second, independent guarantee that stacks on top of the
/// required-member one and that we get for free.
pub fn step<C>(cells: &mut C, ctx: &mut Ctx, state: State, action: Action) -> Step<State, Effect>
where
    C: Handle<Timer, Idle, Start> + Handle<Timer, Running, Tick>,
{
    match (state, action) {
        // -- Idle -------------------------------------------------------
        (State::Idle, Action::Start) => {
            <C as Handle<Timer, Idle, Start>>::handle(cells, ctx, Idle, Start)
        }
        (State::Idle, Action::Tick { .. }) => Step::ignored(),
        (State::Idle, Action::Cancel) => Step::ignored(),

        // -- Running ----------------------------------------------------
        (State::Running(_), Action::Start) => Step::ignored(),
        (State::Running(since), Action::Tick { now }) => {
            <C as Handle<Timer, Running, Tick>>::handle(cells, ctx, Running(since), Tick { now })
        }
        (State::Running(_), Action::Cancel) => Step::go(State::Idle).emit(Effect::StopClock),

        // -- Done -------------------------------------------------------
        (State::Done, Action::Start) => Step::go(State::Running(0)).emit(Effect::StartClock),
        (State::Done, Action::Tick { .. }) => Step::ignored(),
        (State::Done, Action::Cancel) => Step::ignored(),
    }
}

// ---------------------------------------------------------------------------
// 4. Table
// ---------------------------------------------------------------------------

/// The same matrix as inert data. Diagram export, coverage reporting, and
/// reachability analysis are pure functions of this.
pub const TIMER_TABLE: Table<3, 3> = Table {
    machine: "Timer",
    states: ["Idle", "Running", "Done"],
    actions: ["Start", "Tick", "Cancel"],
    initial: Some("Idle"),
    cells: [
        [Cell::Handle, Cell::Ignore, Cell::Ignore],
        [
            Cell::Ignore,
            Cell::Handle,
            Cell::Go {
                target: "Idle",
                effects: &["StopClock"],
            },
        ],
        [
            Cell::Go {
                target: "Running",
                effects: &["StartClock"],
            },
            Cell::Ignore,
            Cell::Ignore,
        ],
    ],
};

// ---------------------------------------------------------------------------
// A developer's implementation
// ---------------------------------------------------------------------------

#[derive(Default)]
struct TimerImpl;

impl Handle<Timer, Idle, Start> for TimerImpl {
    fn handle(&mut self, _ctx: &mut Ctx, _state: Idle, _action: Start) -> Step<State, Effect> {
        Step::go(State::Running(0)).emit(Effect::StartClock)
    }
}

impl Handle<Timer, Running, Tick> for TimerImpl {
    fn handle(&mut self, ctx: &mut Ctx, state: Running, action: Tick) -> Step<State, Effect> {
        // The payload arrives destructured and non-optional: no `if let`, no
        // `matches!`, no unwrap. Rule R2.
        ctx.ticks_seen += 1;
        let elapsed = action.now.saturating_sub(state.0);
        if elapsed >= ctx.limit {
            Step::go(State::Done).emit(Effect::StopClock)
        } else {
            Step::stay()
        }
    }
}

// ---------------------------------------------------------------------------
// Trace replay
// ---------------------------------------------------------------------------

/// Feed a sequence of actions through the machine, collecting every step.
///
/// This is the shape the cross-language conformance runner will drive
/// (Phase 3), which is why it lives here rather than in a test body.
fn replay(
    ctx: &mut Ctx,
    initial: State,
    actions: &[Action],
) -> Vec<(State, Action, Step<State, Effect>)> {
    let mut machine = TimerImpl;
    let mut state = initial;
    let mut log = Vec::new();
    for &action in actions {
        let step = step(&mut machine, ctx, state, action);
        if let Outcome::Go(next) = step.outcome {
            state = next;
        }
        log.push((state, action, step));
    }
    log
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[test]
fn handle_cell_runs_developer_code() {
    let mut ctx = Ctx {
        limit: 5,
        ..Default::default()
    };
    let mut m = TimerImpl;
    let s = step(&mut m, &mut ctx, State::Idle, Action::Start);
    assert_eq!(s.outcome, Outcome::Go(State::Running(0)));
    assert_eq!(
        s.effects.iter().copied().collect::<Vec<_>>(),
        [Effect::StartClock]
    );
}

#[test]
fn static_go_cell_needs_no_developer_code() {
    let mut ctx = Ctx::default();
    let mut m = TimerImpl;
    let s = step(&mut m, &mut ctx, State::Running(3), Action::Cancel);
    assert_eq!(s.outcome, Outcome::Go(State::Idle));
    assert_eq!(
        s.effects.iter().copied().collect::<Vec<_>>(),
        [Effect::StopClock]
    );
}

#[test]
fn ignore_cells_report_ignored_not_stay() {
    let mut ctx = Ctx::default();
    let mut m = TimerImpl;
    for (state, action) in [
        (State::Idle, Action::Tick { now: 1 }),
        (State::Idle, Action::Cancel),
        (State::Running(0), Action::Start),
        (State::Done, Action::Tick { now: 1 }),
        (State::Done, Action::Cancel),
    ] {
        let s = step(&mut m, &mut ctx, state, action);
        assert!(s.is_ignored(), "{state:?} x {action:?} should be Ignored");
        assert!(s.effects.is_empty());
    }
}

#[test]
fn handle_cell_receives_narrowed_payloads() {
    // `running_tick` takes `Running(u32)` and `Tick { now }` directly. If the
    // dispatcher passed `(State, Action)` this test could not be written
    // without a re-bind, which is precisely the boilerplate the design removes.
    let mut ctx = Ctx {
        limit: 10,
        ..Default::default()
    };
    let mut m = TimerImpl;
    let s = <TimerImpl as Handle<Timer, Running, Tick>>::handle(
        &mut m,
        &mut ctx,
        Running(2),
        Tick { now: 20 },
    );
    assert_eq!(s.outcome, Outcome::Go(State::Done));
    assert_eq!(ctx.ticks_seen, 1);
}

#[test]
fn stay_keeps_the_current_state() {
    let mut ctx = Ctx {
        limit: 100,
        ..Default::default()
    };
    let mut m = TimerImpl;
    let s = step(&mut m, &mut ctx, State::Running(0), Action::Tick { now: 1 });
    assert_eq!(s.outcome, Outcome::Stay);
    assert!(!s.is_ignored());
}

#[test]
fn trace_replay_reaches_done() {
    let mut ctx = Ctx {
        limit: 3,
        ..Default::default()
    };
    let log = replay(
        &mut ctx,
        State::Idle,
        &[
            Action::Start,
            Action::Tick { now: 1 },
            Action::Tick { now: 2 },
            Action::Tick { now: 9 },
            Action::Cancel,
        ],
    );
    let states: Vec<State> = log.iter().map(|(s, _, _)| *s).collect();
    assert_eq!(
        states,
        [
            State::Running(0),
            State::Running(0),
            State::Running(0),
            State::Done,
            State::Done, // Done x Cancel is IGNORE
        ]
    );
    assert!(log.last().unwrap().2.is_ignored());
}

#[test]
fn table_matches_the_dispatcher() {
    let c = TIMER_TABLE.coverage();
    assert_eq!(c.total(), 9);
    assert_eq!(c.handle, 2);
    assert_eq!(c.ignore, 5);
    assert_eq!(c.go, 2);
    // Exactly the two `Handle` bounds on `step`.
    assert_eq!(c.required_members(), 2);
}

#[cfg(feature = "alloc")]
#[test]
fn table_renders() {
    let grid = tabula::export::to_grid(&TIMER_TABLE);
    assert!(grid.contains("HANDLE"));
    assert!(grid.contains("GO(Idle, StopClock)"));

    let mermaid = tabula::export::to_mermaid(&TIMER_TABLE);
    assert!(mermaid.contains("Running --> Idle: Cancel / StopClock"));
}
