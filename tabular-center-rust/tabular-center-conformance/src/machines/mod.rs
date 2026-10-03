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
pub mod dead_column;
pub mod effects_never;
pub mod ignore_heavy;
pub mod no_static_entry;
pub mod no_static_exit;
pub mod payload_hoist;
pub mod timer;
pub mod toggle;
pub mod unreachable_heavy;

use crate::{Expect, Spec, Trace};

/// Outcome of one replayed step, in fixture vocabulary.
///
/// Adapters flatten a `Step<S, F>` into this so replay can be written once.
pub struct Observed {
    pub expect: Expect,
    pub effects: Vec<String>,
}

/// Binds one fixture to one real machine.
pub trait Adapter {
    fn name(&self) -> &'static str;

    fn check_table(&self, spec: &Spec) -> Vec<String>;

    fn grid(&self) -> String;

    fn lint(&self) -> String;

    fn mermaid(&self) -> String;

    fn coverage_report(&self) -> String;

    fn replay(&self, trace: &Trace) -> Result<Vec<Observed>, String>;
}

pub fn all() -> Vec<Box<dyn Adapter>> {
    vec![
        Box::new(timer::TimerAdapter),
        Box::new(toggle::ToggleAdapter),
        Box::new(compose::RetryAdapter),
        Box::new(compose::JobAdapter),
        Box::new(effects_never::EffectsNeverAdapter),
        Box::new(payload_hoist::PayloadHoistAdapter),
        Box::new(dead_column::DeadColumnAdapter),
        Box::new(ignore_heavy::IgnoreHeavyAdapter),
        Box::new(no_static_exit::NoStaticExitAdapter),
        Box::new(no_static_entry::NoStaticEntryAdapter),
        Box::new(unreachable_heavy::UnreachableHeavyAdapter),
    ]
}
