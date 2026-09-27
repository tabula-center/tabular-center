//! Adapter for `spec/conformance/effects-never.tbl`.
//!
//! A machine with an uninhabited effect enum. What makes it worth a fixture is
//! what it removes rather than what it adds: with no effect to name, `EMIT`
//! cannot be written at all, since `EMIT!()` is `tabular-center::empty-emit`. The whole
//! vocabulary here is `IGNORE`, `GO!`, `HANDLE` and `UNREACHABLE`.
//!
//! It also pins the reachability gate. `Open` is reached only from the
//! `HANDLE` cell at `(Locked, Unlock)`, so it has no static incoming
//! transition — and the coverage report must stay silent about that, because
//! with a dynamic cell present `statically_unreached` is an approximation
//! rather than a result. `effects-never.cov` fails if any implementation drops
//! the gate.

use std::collections::BTreeMap;

use tabular_center::{transition_matrix, Handle, Outcome, Step};

use super::{Adapter, Observed};
use crate::{Expect, Spec, Trace};

#[derive(Debug, Default)]
pub struct Ctx;

transition_matrix! {
    machine Gate;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { }
    initial Locked;

    states  { Locked, Open }
    actions { Unlock, Lock, Push }

    //            Unlock   Lock          Push
    Locked => [   HANDLE,  IGNORE,       IGNORE  ];
    Open   => [   IGNORE,  GO!(Locked),  HANDLE  ];
}

struct Impl;

impl Handle<Gate, Locked, Unlock> for Impl {
    fn handle(&mut self, _c: &mut Ctx, _s: Locked, _a: Unlock) -> Step<State, Effect> {
        // The only route into `Open`, and it is deliberately dynamic: a
        // statically resolvable transition here would make the matrix fully
        // static and defeat the gate this fixture exists to pin.
        Step::go(State::Open(Open))
    }
}

impl Handle<Gate, Open, Push> for Impl {
    fn handle(&mut self, _c: &mut Ctx, _s: Open, _a: Push) -> Step<State, Effect> {
        Step::stay()
    }
}

pub struct EffectsNeverAdapter;

fn state_from(name: &str) -> Result<State, String> {
    Ok(match name {
        "Locked" => State::Locked(Locked),
        "Open" => State::Open(Open),
        _ => return Err(format!("effects-never: unknown state `{name}`")),
    })
}

fn action_from(name: &str) -> Result<Action, String> {
    Ok(match name {
        "Unlock" => Action::Unlock(Unlock),
        "Lock" => Action::Lock(Lock),
        "Push" => Action::Push(Push),
        _ => return Err(format!("effects-never: unknown action `{name}`")),
    })
}

impl Adapter for EffectsNeverAdapter {
    fn name(&self) -> &'static str {
        "effects-never"
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
            // Always empty: `Effect` has no variants, so nothing can construct
            // one. Collected the same way as every other adapter rather than
            // short-circuited to `vec![]`, so the trace assertions are testing
            // the real path.
            let effects = step.effects.iter().map(|e| format!("{e:?}")).collect();
            let expect = match step.outcome {
                Outcome::Stay => Expect::Stay,
                Outcome::Ignored => Expect::Ignored,
                Outcome::Go(next) => {
                    state = next;
                    let name = match next {
                        State::Locked(_) => "Locked",
                        State::Open(_) => "Open",
                    };
                    Expect::Go {
                        state: name.to_string(),
                        fields: BTreeMap::new(),
                    }
                }
            };
            out.push(Observed { expect, effects });
        }
        Ok(out)
    }
}
