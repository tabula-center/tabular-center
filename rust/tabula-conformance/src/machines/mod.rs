//! Per-fixture adapters.
//!
//! Each fixture needs a real machine plus a small mapping from the trace's
//! action names and payload fields to concrete values. That mapping is the
//! *only* per-fixture code; parsing, table checking, and replay are shared.
//!
//! Kotlin and Swift will need the same shape of adapter, which is the point:
//! a fixture with no adapter in some language reports as **skipped**, never as
//! passed.

pub mod compose;
pub mod timer;
pub mod toggle;

use crate::{Expect, Spec, Trace};

/// Outcome of one replayed step, in fixture vocabulary.
///
/// Adapters flatten a `Step<S, F>` into this so replay can be written once.
pub struct Observed {
    /// `go <State>`, `stay`, or `ignored`.
    pub expect: Expect,
    /// Effects emitted, in order, by last path segment.
    pub effects: Vec<String>,
}

/// Binds one fixture to one real machine.
pub trait Adapter {
    /// Fixture name; `<name>.tbl` and `traces/<name>.trace`.
    fn name(&self) -> &'static str;

    /// Compare the generated `TABLE` against the fixture.
    fn check_table(&self, spec: &Spec) -> Vec<String>;

    /// Replay one trace, returning one `Observed` per step.
    ///
    /// Returns `Err` when the trace names an action or state the adapter does
    /// not know, which is a fixture/adapter mismatch rather than a machine
    /// failure and must be reported differently.
    fn replay(&self, trace: &Trace) -> Result<Vec<Observed>, String>;
}

/// Every adapter that has landed.
pub fn all() -> Vec<Box<dyn Adapter>> {
    vec![
        Box::new(timer::TimerAdapter),
        Box::new(toggle::ToggleAdapter),
        Box::new(compose::RetryAdapter),
        Box::new(compose::JobAdapter),
    ]
}
