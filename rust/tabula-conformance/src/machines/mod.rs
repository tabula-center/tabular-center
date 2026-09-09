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

    /// The generated `TABLE` rendered as an aligned grid.
    ///
    /// Snapshotted to `<name>.grid` so a PR that changes machine behaviour
    /// shows a *table* diff. Reviewing a matrix is what this library is for;
    /// reviewing a `match` arm is what it exists to avoid.
    fn grid(&self) -> String;

    /// Lint findings for the generated `TABLE`, one per line.
    fn lint(&self) -> String;

    /// The generated `TABLE` rendered as a PlantUML state diagram.
    ///
    /// Snapshotted for the same reason the grid is, and for one more: until
    /// this existed nothing compared a line of diagram output across the three
    /// implementations, and they had already drifted. Rust emitted every `GO`
    /// edge before every self-loop while Kotlin and Swift interleaved them in
    /// cell order.
    ///
    /// PlantUML rather than mermaid because it renders every cell kind the
    /// other two formats do -- one walk feeds all three -- and its `A --> B :
    /// label` line is the easiest of them to read in a diff. One golden per
    /// fixture is enough to pin the walk they share.
    fn plantuml(&self) -> String;

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
