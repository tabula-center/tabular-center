//! Adapters for `nested-delegate.tbl` and its child `retry.tbl`.
//!
//! Two adapters over one pair of machines, because the child must be
//! conformant *on its own*: being composed does not change it, and a child
//! that only works inside its parent is not a reusable machine.

use std::collections::BTreeMap;

use tabula::{transition_matrix, Delegate, Handle, Outcome, Step};

use super::{Adapter, Observed};
use crate::{Expect, Spec, Trace};

pub mod retry {
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

pub mod job {
    use super::*;

    /// The parent context **contains** the child's, so `child_ctx` is a field
    /// access and the child never sees parent data it has no business with.
    #[derive(Debug, Default)]
    pub struct Ctx {
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

        //             Run                Tick               Cancel
        Idle     => [  HANDLE,            IGNORE,            IGNORE                 ];
        Retrying => [  DELEGATE!(retry),  DELEGATE!(retry),  GO!(Done, Log) ];
        Done     => [  IGNORE,            IGNORE,            IGNORE                 ];
    }
}

struct Impl;

impl Handle<job::Job, job::Idle, job::Run> for Impl {
    fn handle(
        &mut self,
        _c: &mut job::Ctx,
        _s: job::Idle,
        _a: job::Run,
    ) -> Step<job::State, job::Effect> {
        Step::go(job::State::Retrying(job::Retrying {
            child: retry::State::Ready(retry::Ready),
        }))
        .emit(job::Log.into())
    }
}

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

/// A child reaching its terminal state is the parent's cue to leave.
fn embed_child(child: retry::State) -> job::State {
    match child {
        retry::State::Exhausted(_) => job::State::Done(job::Done),
        other => job::State::Retrying(job::Retrying { child: other }),
    }
}

fn lift_effect(e: retry::Effect) -> job::Effect {
    match e {
        retry::Effect::Sleep(_) => job::Effect::Backoff(job::Backoff),
        retry::Effect::GiveUp(_) => job::Effect::Alert(job::Alert),
    }
}

// The lens is per (parent state, child); only the action prism is per cell.
impl tabula::Lens<job::Job, job::Retrying, retry::Marker> for Impl {
    fn child_state(&mut self, s: &job::Retrying) -> retry::State {
        s.child
    }
    fn embed(&mut self, _s: job::Retrying, child: retry::State) -> job::State {
        embed_child(child)
    }
    fn lift(&mut self, e: retry::Effect) -> job::Effect {
        lift_effect(e)
    }
    fn child_ctx<'a>(&mut self, c: &'a mut job::Ctx) -> &'a mut retry::Ctx {
        &mut c.retry
    }
}

macro_rules! job_prism {
    ($av:ty, $child:expr) => {
        impl Delegate<job::Job, job::Retrying, $av, retry::Marker> for Impl {
            fn to_child(
                &mut self,
                _c: &mut job::Ctx,
                _s: &job::Retrying,
                _a: $av,
            ) -> Option<retry::Action> {
                Some($child)
            }
        }
    };
}

job_prism!(job::Run, retry::Action::Attempt(retry::Attempt));
job_prism!(job::Tick, retry::Action::Elapsed(retry::Elapsed));

// ---------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------

fn retry_state(name: &str, f: &BTreeMap<String, i64>) -> Result<retry::State, String> {
    Ok(match name {
        "Ready" => retry::State::Ready(retry::Ready),
        "Exhausted" => retry::State::Exhausted(retry::Exhausted),
        "Waiting" => retry::State::Waiting(retry::Waiting {
            attempt: f.get("attempt").copied().unwrap_or(1) as u32,
        }),
        _ => return Err(format!("retry: unknown state `{name}`")),
    })
}

fn retry_action(name: &str) -> Result<retry::Action, String> {
    Ok(match name {
        "Attempt" => retry::Action::Attempt(retry::Attempt),
        "Elapsed" => retry::Action::Elapsed(retry::Elapsed),
        "Abort" => retry::Action::Abort(retry::Abort),
        _ => return Err(format!("retry: unknown action `{name}`")),
    })
}

pub struct RetryAdapter;

impl Adapter for RetryAdapter {
    fn name(&self) -> &'static str {
        "retry"
    }

    fn check_table(&self, spec: &Spec) -> Vec<String> {
        crate::check_table(&retry::TABLE, spec)
    }

    fn grid(&self) -> String {
        tabula::export::to_grid(&retry::TABLE)
    }

    fn lint(&self) -> String {
        tabula::lint::report_with_payloads(&retry::TABLE, retry::PAYLOADS)
    }

    fn plantuml(&self) -> String {
        tabula::export::to_plantuml(&retry::TABLE)
    }

    fn coverage_report(&self) -> String {
        tabula::export::to_coverage_report(&retry::TABLE)
    }

    fn replay(&self, trace: &Trace) -> Result<Vec<Observed>, String> {
        let mut ctx = retry::Ctx {
            max_attempts: trace.ctx.get("max_attempts").copied().unwrap_or(1) as u32,
        };
        let mut state = retry_state(&trace.from, &trace.from_fields)?;
        let mut out = vec![];

        for st in &trace.steps {
            let step = retry::step(&mut Impl, &mut ctx, state, retry_action(&st.action)?);
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
                    let mut fields = BTreeMap::new();
                    let name = match next {
                        retry::State::Ready(_) => "Ready",
                        retry::State::Exhausted(_) => "Exhausted",
                        retry::State::Waiting(w) => {
                            if want.contains_key("attempt") {
                                fields.insert("attempt".to_string(), w.attempt as i64);
                            }
                            "Waiting"
                        }
                    };
                    Expect::Go {
                        state: name.to_string(),
                        fields,
                    }
                }
            };
            out.push(Observed { expect, effects });
        }
        Ok(out)
    }
}

pub struct JobAdapter;

impl Adapter for JobAdapter {
    fn name(&self) -> &'static str {
        "nested-delegate"
    }

    fn check_table(&self, spec: &Spec) -> Vec<String> {
        crate::check_table(&job::TABLE, spec)
    }

    fn grid(&self) -> String {
        tabula::export::to_grid(&job::TABLE)
    }

    fn lint(&self) -> String {
        tabula::lint::report_with_payloads(&job::TABLE, job::PAYLOADS)
    }

    fn plantuml(&self) -> String {
        tabula::export::to_plantuml(&job::TABLE)
    }

    fn coverage_report(&self) -> String {
        tabula::export::to_coverage_report(&job::TABLE)
    }

    fn replay(&self, trace: &Trace) -> Result<Vec<Observed>, String> {
        let mut ctx = job::Ctx {
            retry: retry::Ctx {
                max_attempts: trace.ctx.get("max_attempts").copied().unwrap_or(1) as u32,
            },
        };

        // `from Retrying child_attempt=N` starts the child in Waiting{N};
        // absent means Ready. The trace format is flat by design, so a nested
        // state is addressed by a prefixed field rather than by nesting.
        let mut state = match trace.from.as_str() {
            "Idle" => job::State::Idle(job::Idle),
            "Done" => job::State::Done(job::Done),
            "Retrying" => job::State::Retrying(job::Retrying {
                child: match trace.from_fields.get("child_attempt") {
                    Some(&n) => retry::State::Waiting(retry::Waiting { attempt: n as u32 }),
                    None => retry::State::Ready(retry::Ready),
                },
            }),
            other => return Err(format!("job: unknown state `{other}`")),
        };

        let mut out = vec![];
        for st in &trace.steps {
            let action = match st.action.as_str() {
                "Run" => job::Action::Run(job::Run),
                "Tick" => job::Action::Tick(job::Tick),
                "Cancel" => job::Action::Cancel(job::Cancel),
                other => return Err(format!("job: unknown action `{other}`")),
            };
            let step = job::step(&mut Impl, &mut ctx, state, action);
            let effects = step.effects.iter().map(|e| format!("{e:?}")).collect();
            let expect = match step.outcome {
                Outcome::Stay => Expect::Stay,
                Outcome::Ignored => Expect::Ignored,
                Outcome::Go(next) => {
                    state = next;
                    let name = match next {
                        job::State::Idle(_) => "Idle",
                        job::State::Done(_) => "Done",
                        job::State::Retrying(_) => "Retrying",
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
