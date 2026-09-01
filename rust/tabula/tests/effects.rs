//! The effect surface: one required member per effect variant.
//!
//! Adding an effect variant breaks every handler's build, by the same
//! mechanism the transition side uses. This falls out for free once effects
//! are a *generated* sum type — knowing the variants is the whole trick, and
//! it is exactly what `effect Effect;` (naming a hand-written enum) could
//! never provide.

use tabula::{transition_matrix, Driver, Handle, Perform, Step};

pub struct Ctx {
    pub limit: u32,
    pub log: Vec<String>,
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

    //            Start                              Tick     Cancel
    Idle    => [  HANDLE,                            IGNORE,  IGNORE                            ];
    Running => [  IGNORE,                            HANDLE,  GO!(Idle, StopClock { reason: 1 }) ];
    Done    => [  GO!(Running { since: 0 }, StartClock), IGNORE, IGNORE                         ];
}

#[derive(Default)]
struct Impl;

impl Handle<Timer, Idle, Start> for Impl {
    fn handle(&mut self, _c: &mut Ctx, _s: Idle, _a: Start) -> Step<State, Effect> {
        Step::go(State::Running(Running { since: 0 })).emit(StartClock.into())
    }
}

impl Handle<Timer, Running, Tick> for Impl {
    fn handle(&mut self, c: &mut Ctx, s: Running, a: Tick) -> Step<State, Effect> {
        if a.now.saturating_sub(s.since) >= c.limit {
            Step::go(State::Done(Done)).emit(StopClock { reason: 2 }.into())
        } else {
            Step::stay()
        }
    }
}

// One `Perform` impl per effect variant. Delete either and this file stops
// compiling with `the trait bound Impl: Perform<Timer, StopClock> is not
// satisfied` -- the same error shape as a missing cell.
impl Perform<Timer, StartClock> for Impl {
    fn perform(&mut self, c: &mut Ctx, _e: StartClock) -> Option<Action> {
        c.log.push("start".into());
        None
    }
}

impl Perform<Timer, StopClock> for Impl {
    fn perform(&mut self, c: &mut Ctx, e: StopClock) -> Option<Action> {
        // The payload arrives destructured, exactly as a cell's does.
        c.log.push(format!("stop:{}", e.reason));
        None
    }
}

fn ctx(limit: u32) -> Ctx {
    Ctx {
        limit,
        log: Vec::new(),
    }
}

#[test]
fn perform_dispatches_to_the_variant_handler() {
    let mut c = ctx(5);
    let out = perform(&mut Impl, &mut c, StopClock { reason: 7 }.into());
    assert_eq!(out, None);
    assert_eq!(c.log, ["stop:7"]);
}

#[test]
fn effect_payloads_are_narrowed() {
    let mut c = ctx(5);
    perform(
        &mut Impl,
        &mut c,
        Effect::StopClock(StopClock { reason: 42 }),
    );
    assert_eq!(c.log, ["stop:42"]);
}

#[test]
fn step_and_perform_compose_through_the_driver() {
    // The two halves meet here: `step` returns effects as data, `perform`
    // carries them out, and the driver enqueues anything they produce.
    let mut c = ctx(3);
    let mut d: Driver<State, Action, 8> = Driver::new(State::Idle(Idle));
    let mut cells = Impl;

    let p = d
        .dispatch(
            Action::Start(Start),
            |s, a| step(&mut cells, &mut c, s, a),
            |_e| None,
        )
        .unwrap();

    assert_eq!(p.transitions, 1);
    assert_eq!(p.effects, 1);
    assert_eq!(d.state(), State::Running(Running { since: 0 }));
}

#[test]
fn table_records_effects_by_bare_variant_name() {
    // `StopClock { reason: 1 }` appears as `StopClock`, so grids and diagrams
    // stay readable rather than carrying struct literals.
    assert_eq!(TABLE.cell(1, 2).static_effects(), &["StopClock"]);
    assert_eq!(TABLE.cell(2, 0).static_effects(), &["StartClock"]);
}

/// A machine that emits nothing.
mod silent {
    use super::*;

    pub struct Ctx;

    transition_matrix! {
        machine Silent;
        context Ctx;
        state   State;
        action  Action;
        effects Effect { }
        initial Off;

        states  { Off, On }
        actions { Flip }

        Off => [ GO!(On)  ];
        On  => [ GO!(Off) ];
    }
}

#[test]
fn a_machine_can_declare_no_effects_at_all() {
    // `effects Effect { }` is an uninhabited enum: cells do IO directly and
    // there is nothing to handle. A supported mode, not a degraded one --
    // `Handlers` is satisfied by everything, because it demands nothing.
    struct Nothing;
    let mut c = silent::Ctx;
    let s = silent::step(
        &mut Nothing,
        &mut c,
        silent::State::Off(silent::Off),
        silent::Action::Flip(silent::Flip),
    );
    assert!(s.is_transition());
    assert!(s.effects.is_empty());
}
