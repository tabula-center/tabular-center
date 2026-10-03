//! Adapter for `spec/conformance/unreachable-heavy.tbl`.
//!
//! The only coverage for `tabular-center::unreachable-heavy`: three `UNREACHABLE`
//! cells of twelve, which is `UNREACHABLE_HEAVY_PERCENT` exactly -- the
//! fixture sits on the boundary so `>` instead of `>=` fails it.
//!
//! `UNREACHABLE` generates no member and compiles to a trap, so the only
//! member here is `Dialing`/`Ack`. The traces never visit a trapping cell;
//! the fixture's claim about them lives in the table, the grid, the lint and
//! the coverage report, not in behaviour.
//!
//! `Up` is entered only through that `HANDLE`, and the matrix is not fully
//! static, which is why `no-static-entry` stays quiet about it.

use std::collections::BTreeMap;

use tabular_center::{transition_matrix, Handle, Outcome, Step};

use super::{Adapter, Observed};
use crate::{Expect, Spec, Trace};

#[derive(Debug, Default)]
pub struct Ctx {
    pub accept: bool,
}

transition_matrix! {
    machine Link;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { Pong }
    initial Down;

    states  { Down, Dialing, Up }
    actions { Dial, Ack, Hangup, Ping }

    //               Dial           Ack            Hangup       Ping
    Down    => [     GO!(Dialing),  UNREACHABLE,   IGNORE,      IGNORE       ];
    Dialing => [     UNREACHABLE,   HANDLE,        GO!(Down),   IGNORE       ];
    Up      => [     UNREACHABLE,   IGNORE,        GO!(Down),   EMIT!(Pong)  ];
}

struct Impl;

impl Handle<Link, Dialing, Ack> for Impl {
    fn handle(&mut self, c: &mut Ctx, _s: Dialing, _a: Ack) -> Step<State, Effect> {
        if c.accept {
            Step::go(State::Up(Up))
        } else {
            Step::stay()
        }
    }
}

pub struct UnreachableHeavyAdapter;

fn state_from(name: &str) -> Result<State, String> {
    Ok(match name {
        "Down" => State::Down(Down),
        "Dialing" => State::Dialing(Dialing),
        "Up" => State::Up(Up),
        _ => return Err(format!("unreachable-heavy: unknown state `{name}`")),
    })
}

fn action_from(name: &str) -> Result<Action, String> {
    Ok(match name {
        "Dial" => Action::Dial(Dial),
        "Ack" => Action::Ack(Ack),
        "Hangup" => Action::Hangup(Hangup),
        "Ping" => Action::Ping(Ping),
        _ => return Err(format!("unreachable-heavy: unknown action `{name}`")),
    })
}

fn name_of(s: State) -> &'static str {
    match s {
        State::Down(_) => "Down",
        State::Dialing(_) => "Dialing",
        State::Up(_) => "Up",
    }
}

impl Adapter for UnreachableHeavyAdapter {
    fn name(&self) -> &'static str {
        "unreachable-heavy"
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
        let mut ctx = Ctx {
            accept: trace.ctx.get("accept").copied().unwrap_or(0) != 0,
        };
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
