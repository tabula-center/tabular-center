//! Adapter for `spec/conformance/ignore-heavy.tbl`.
//!
//! The only coverage for `tabular-center::ignore-heavy`: 15 of 20 cells `IGNORE`,
//! which is 75% against `IGNORE_HEAVY_PERCENT`. Four states each answering one
//! action, which is the shape the lint's "consider splitting this machine" is
//! about.
//!
//! 4x5 rather than the suite's usual 3x3 because the shape is forced -- every
//! row and every column needs a live cell or `dead-row`/`dead-column` fire
//! instead, and three actions cannot get past 66%. See the note in the `.tbl`.
//! No payloads, so `payload-hoist` cannot fire, and the `HANDLE` cells make the
//! matrix not fully static, which gates `no-static-entry` off.

use std::collections::BTreeMap;

use tabular_center::{transition_matrix, Handle, Outcome, Step};

use super::{Adapter, Observed};
use crate::{Expect, Spec, Trace};

#[derive(Debug, Default)]
pub struct Ctx;

transition_matrix! {
    machine Poll;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { }
    initial Idle;

    states  { Idle, Armed, Firing, Spent }
    actions { Arm, Tick, Fire, Reset, Abort }

    //              Arm      Tick     Fire     Reset      Abort
    Idle   => [     HANDLE,  IGNORE,  IGNORE,  IGNORE,    IGNORE     ];
    Armed  => [     IGNORE,  HANDLE,  IGNORE,  IGNORE,    GO!(Idle)  ];
    Firing => [     IGNORE,  IGNORE,  HANDLE,  IGNORE,    IGNORE     ];
    Spent  => [     IGNORE,  IGNORE,  IGNORE,  GO!(Idle), IGNORE     ];
}

struct Impl;

impl Handle<Poll, Idle, Arm> for Impl {
    fn handle(&mut self, _c: &mut Ctx, _s: Idle, _a: Arm) -> Step<State, Effect> {
        Step::go(State::Armed(Armed))
    }
}

impl Handle<Poll, Armed, Tick> for Impl {
    fn handle(&mut self, _c: &mut Ctx, _s: Armed, _a: Tick) -> Step<State, Effect> {
        Step::stay()
    }
}

impl Handle<Poll, Firing, Fire> for Impl {
    fn handle(&mut self, _c: &mut Ctx, _s: Firing, _a: Fire) -> Step<State, Effect> {
        Step::go(State::Spent(Spent))
    }
}

pub struct IgnoreHeavyAdapter;

fn state_from(name: &str) -> Result<State, String> {
    Ok(match name {
        "Idle" => State::Idle(Idle),
        "Armed" => State::Armed(Armed),
        "Firing" => State::Firing(Firing),
        "Spent" => State::Spent(Spent),
        _ => return Err(format!("ignore-heavy: unknown state `{name}`")),
    })
}

fn action_from(name: &str) -> Result<Action, String> {
    Ok(match name {
        "Arm" => Action::Arm(Arm),
        "Tick" => Action::Tick(Tick),
        "Fire" => Action::Fire(Fire),
        "Reset" => Action::Reset(Reset),
        "Abort" => Action::Abort(Abort),
        _ => return Err(format!("ignore-heavy: unknown action `{name}`")),
    })
}

fn name_of(s: State) -> &'static str {
    match s {
        State::Idle(_) => "Idle",
        State::Armed(_) => "Armed",
        State::Firing(_) => "Firing",
        State::Spent(_) => "Spent",
    }
}

impl Adapter for IgnoreHeavyAdapter {
    fn name(&self) -> &'static str {
        "ignore-heavy"
    }

    fn check_table(&self, spec: &Spec) -> Vec<String> {
        crate::check_table(&TABLE, spec)
    }

    fn grid(&self) -> String {
        tabular_center::export::to_grid(&TABLE)
    }

    fn mermaid(&self) -> String {
        tabular_center::export::to_mermaid(&TABLE)
    }

    fn lint(&self) -> String {
        tabular_center::lint::report_with_payloads(&TABLE, PAYLOADS)
    }

    fn coverage_report(&self) -> String {
        tabular_center::export::to_coverage_report(&TABLE)
    }

    fn replay(&self, trace: &Trace) -> Result<Vec<Observed>, String> {
        let mut ctx = Ctx;
        let mut cells = Impl;
        let mut state = state_from(&trace.from)?;
        let mut out = vec![];

        for st in &trace.steps {
            let action = action_from(&st.action)?;
            let step = step(&mut cells, &mut ctx, state, action);
            let effects = step.effects.iter().map(|e| format!("{e:?}")).collect();
            let expect = match step.outcome {
                Outcome::Stay => Expect::Stay,
                Outcome::Ignored => Expect::Ignored,
                Outcome::Go(next) => {
                    state = next;
                    Expect::Go {
                        state: name_of(next).to_string(),
                        fields: BTreeMap::new(),
                    }
                }
            };
            out.push(Observed { expect, effects });
        }
        Ok(out)
    }
}
