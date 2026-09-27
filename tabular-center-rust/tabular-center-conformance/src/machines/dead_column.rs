//! Adapter for `spec/conformance/dead-column.tbl`.
//!
//! The only coverage for `tabular-center::dead-column`, and the second fixture whose
//! point is a warning rather than a behaviour.
//!
//! `Refund` is `IGNORE` in every row. Everything else is shaped to keep the
//! other six lints quiet, so the `.lint` golden holds exactly one line — see
//! the notes in the `.tbl`, including why 6 of 9 `IGNORE` (66%) sits
//! deliberately near `IGNORE_HEAVY_PERCENT` rather than comfortably below it.
//!
//! `credit` is on one state. Three would trip `payload-hoist` and the fixture
//! would be testing two lints, neither cleanly.

use std::collections::BTreeMap;

use tabular_center::{transition_matrix, Handle, Outcome, Step};

use super::{Adapter, Observed};
use crate::{Expect, Spec, Trace};

#[derive(Debug, Default)]
pub struct Ctx {
    pub price: u32,
}

transition_matrix! {
    machine Vend;
    context Ctx;
    state   State;
    action  Action;
    effects Effect { }
    initial Idle;

    states  { Idle, Charged { credit: u32 }, Dispensing }
    actions { Insert, Select, Refund }

    //                  Insert         Select   Refund
    Idle       => [     HANDLE,        IGNORE,  IGNORE  ];
    Charged    => [     IGNORE,        HANDLE,  IGNORE  ];
    Dispensing => [     GO!(Idle),     IGNORE,  IGNORE  ];
}

struct Impl;

impl Handle<Vend, Idle, Insert> for Impl {
    fn handle(&mut self, _c: &mut Ctx, _s: Idle, _a: Insert) -> Step<State, Effect> {
        Step::go(State::Charged(Charged { credit: 1 }))
    }
}

/// `stay`, not `ignored`, when the credit is short.
///
/// The distinction the third trace exists for: this cell is `HANDLE` and
/// refuses, while `Charged`/`Insert` beside it is `IGNORE` and never runs at
/// all. An implementation that collapsed the two would pass every other
/// fixture in the suite.
impl Handle<Vend, Charged, Select> for Impl {
    fn handle(&mut self, c: &mut Ctx, s: Charged, _a: Select) -> Step<State, Effect> {
        if s.credit >= c.price {
            Step::go(State::Dispensing(Dispensing))
        } else {
            Step::stay()
        }
    }
}

pub struct DeadColumnAdapter;

fn state_from(name: &str, f: &BTreeMap<String, i64>) -> Result<State, String> {
    Ok(match name {
        "Idle" => State::Idle(Idle),
        "Charged" => State::Charged(Charged {
            credit: f.get("credit").copied().unwrap_or(0) as u32,
        }),
        "Dispensing" => State::Dispensing(Dispensing),
        _ => return Err(format!("dead-column: unknown state `{name}`")),
    })
}

fn action_from(name: &str) -> Result<Action, String> {
    Ok(match name {
        "Insert" => Action::Insert(Insert),
        "Select" => Action::Select(Select),
        "Refund" => Action::Refund(Refund),
        _ => return Err(format!("dead-column: unknown action `{name}`")),
    })
}

fn describe(s: State, want: &BTreeMap<String, i64>) -> (String, BTreeMap<String, i64>) {
    let (name, credit) = match s {
        State::Idle(_) => ("Idle", None),
        State::Charged(v) => ("Charged", Some(v.credit)),
        State::Dispensing(_) => ("Dispensing", None),
    };
    let mut fields = BTreeMap::new();
    if let Some(c) = credit.filter(|_| want.contains_key("credit")) {
        fields.insert("credit".to_string(), c as i64);
    }
    (name.to_string(), fields)
}

impl Adapter for DeadColumnAdapter {
    fn name(&self) -> &'static str {
        "dead-column"
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
            price: trace.ctx.get("price").copied().unwrap_or(0) as u32,
        };
        let mut cells = Impl;
        let mut state = state_from(&trace.from, &trace.from_fields)?;
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
                    let want = match &st.expect {
                        Expect::Go { fields, .. } => fields.clone(),
                        _ => BTreeMap::new(),
                    };
                    let (name, fields) = describe(next, &want);
                    Expect::Go {
                        state: name,
                        fields,
                    }
                }
            };
            out.push(Observed { expect, effects });
        }
        Ok(out)
    }
}
