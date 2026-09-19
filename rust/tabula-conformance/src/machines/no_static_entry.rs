//! Adapter for `spec/conformance/no-static-entry.tbl`.
//!
//! The only coverage for `tabula::no-static-entry`: `Jammed` has a row and a
//! way out, and nothing in the matrix leads in. The matrix is **fully
//! static** -- no `HANDLE`, `DELEGATE` or `UNREACHABLE` -- which is the gate
//! the lint needs before it may speak. `effects-never` pins the gate shut;
//! this pins it open.
//!
//! Fully static also means there is no cell surface at all: `Cells` has no
//! bounds, and `Impl` is an empty struct that exists only because `step`
//! takes one. A machine written entirely in one-word cells is a supported
//! shape, and this is the first fixture to exercise it.
//!
//! `Jammed`'s `EMIT!(Thud)` is `stay` plus an effect, not a transition into
//! `Jammed`; a reachability walk that counted it as one would go silent here.

use std::collections::BTreeMap;

use tabula::{transition_matrix, Outcome};

use super::{Adapter, Observed};
use crate::{Expect, Spec, Trace};

#[derive(Debug, Default)]
pub struct Ctx;

transition_matrix! {
    machine Door;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { Thud }
    initial Closed;

    states  { Closed, Open, Jammed }
    actions { Push, Pull, Kick }

    //              Push           Pull          Kick
    Closed => [     GO!(Open),     IGNORE,       IGNORE        ];
    Open   => [     IGNORE,        GO!(Closed),  IGNORE        ];
    Jammed => [     EMIT!(Thud),   IGNORE,       GO!(Closed)   ];
}

/// No members to implement: every cell is static.
struct Impl;

pub struct NoStaticEntryAdapter;

fn state_from(name: &str) -> Result<State, String> {
    Ok(match name {
        "Closed" => State::Closed(Closed),
        "Open" => State::Open(Open),
        "Jammed" => State::Jammed(Jammed),
        _ => return Err(format!("no-static-entry: unknown state `{name}`")),
    })
}

fn action_from(name: &str) -> Result<Action, String> {
    Ok(match name {
        "Push" => Action::Push(Push),
        "Pull" => Action::Pull(Pull),
        "Kick" => Action::Kick(Kick),
        _ => return Err(format!("no-static-entry: unknown action `{name}`")),
    })
}

fn name_of(s: State) -> &'static str {
    match s {
        State::Closed(_) => "Closed",
        State::Open(_) => "Open",
        State::Jammed(_) => "Jammed",
    }
}

impl Adapter for NoStaticEntryAdapter {
    fn name(&self) -> &'static str {
        "no-static-entry"
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
