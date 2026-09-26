//! Adapter for `spec/conformance/no-static-exit.tbl`.
//!
//! The only coverage for `tabula::no-static-exit`: `Fault` can be entered and,
//! as far as the matrix can prove, never left. Its row is
//! `[IGNORE, EMIT(Alarm), IGNORE]`, and `EMIT` is `stay` plus an effect, never
//! a transition -- the `emit-stays-put` trace fails an implementation that
//! treats it as a self-`GO`.
//!
//! That single `EMIT` is also what keeps `dead-row` from subsuming the lint:
//! `dead-row` needs every cell to be `IGNORE`.
//!
//! `Idle`'s `HANDLE` is the only dynamic cell, and it keeps the matrix from
//! being fully static, which is why `no-static-entry` stays quiet about
//! `Fault` even though nothing in the matrix enters it.

use std::collections::BTreeMap;

use tabula::{transition_matrix, Handle, Outcome, Step};

use super::{Adapter, Observed};
use crate::{Expect, Spec, Trace};

#[derive(Debug, Default)]
pub struct Ctx;

transition_matrix! {
    machine Beacon;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { Flash, Alarm }
    initial Idle;

    states  { Idle, Blinking, Fault }
    actions { Start, Pulse, Clear }

    //                Start    Pulse          Clear
    Idle     => [     HANDLE,  IGNORE,        IGNORE     ];
    Blinking => [     IGNORE,  EMIT!(Flash),  GO!(Idle)  ];
    Fault    => [     IGNORE,  EMIT!(Alarm),  IGNORE     ];
}

struct Impl;

impl Handle<Beacon, Idle, Start> for Impl {
    fn handle(&mut self, _c: &mut Ctx, _s: Idle, _a: Start) -> Step<State, Effect> {
        Step::go(State::Blinking(Blinking))
    }
}

pub struct NoStaticExitAdapter;

fn state_from(name: &str) -> Result<State, String> {
    Ok(match name {
        "Idle" => State::Idle(Idle),
        "Blinking" => State::Blinking(Blinking),
        "Fault" => State::Fault(Fault),
        _ => return Err(format!("no-static-exit: unknown state `{name}`")),
    })
}

fn action_from(name: &str) -> Result<Action, String> {
    Ok(match name {
        "Start" => Action::Start(Start),
        "Pulse" => Action::Pulse(Pulse),
        "Clear" => Action::Clear(Clear),
        _ => return Err(format!("no-static-exit: unknown action `{name}`")),
    })
}

fn name_of(s: State) -> &'static str {
    match s {
        State::Idle(_) => "Idle",
        State::Blinking(_) => "Blinking",
        State::Fault(_) => "Fault",
    }
}

impl Adapter for NoStaticExitAdapter {
    fn name(&self) -> &'static str {
        "no-static-exit"
    }

    fn check_table(&self, spec: &Spec) -> Vec<String> {
        crate::check_table(&TABLE, spec)
    }

    fn grid(&self) -> String {
        tabula::export::to_grid(&TABLE)
    }

    fn mermaid(&self) -> String {
        tabula::export::to_mermaid(&TABLE)
    }

    fn lint(&self) -> String {
        tabula::lint::report_with_payloads(&TABLE, PAYLOADS)
    }

    fn coverage_report(&self) -> String {
        tabula::export::to_coverage_report(&TABLE)
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
