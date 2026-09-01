//! Runs every fixture in `spec/conformance` against the Rust implementation.

use std::path::PathBuf;
use std::process::ExitCode;

use tabula_conformance::machines::{all, Adapter};
use tabula_conformance::{last_segment, load, Expect, Trace};

fn spec_root() -> PathBuf {
    // The crate lives at rust/tabula-conformance; the spec is repo-relative.
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/conformance")
}

fn check_trace(adapter: &dyn Adapter, trace: &Trace) -> Vec<String> {
    let observed = match adapter.replay(trace) {
        Ok(o) => o,
        Err(e) => return vec![format!("{}: {e}", trace.name)],
    };

    let mut errs = vec![];
    for (i, (want, got)) in trace.steps.iter().zip(observed.iter()).enumerate() {
        let at = format!("{}[{}] {}", trace.name, i, want.action);

        if want.expect != got.expect {
            errs.push(format!(
                "{at}: got `{}`, want `{}`",
                got.expect, want.expect
            ));
        }

        let got_eff: Vec<&str> = got.effects.iter().map(|e| last_segment(e)).collect();
        let want_eff: Vec<&str> = want.effects.iter().map(|e| last_segment(e)).collect();
        if got_eff != want_eff {
            errs.push(format!("{at}: effects got {got_eff:?}, want {want_eff:?}"));
        }
    }
    errs
}

fn main() -> ExitCode {
    let root = spec_root();
    let mut failed = 0usize;
    let (mut tables, mut steps) = (0usize, 0usize);

    for adapter in all() {
        let name = adapter.name();
        let (spec, traces) = match load(&root, name) {
            Ok(v) => v,
            Err(e) => {
                println!("FAIL {name}: {e}");
                failed += 1;
                continue;
            }
        };

        let mut errs = adapter.check_table(&spec);
        tables += 1;

        for t in &traces {
            steps += t.steps.len();
            errs.extend(check_trace(adapter.as_ref(), t));
        }

        if errs.is_empty() {
            println!(
                "ok   {name}  ({} states x {} actions, {} traces)",
                spec.states.len(),
                spec.actions.len(),
                traces.len()
            );
        } else {
            println!("FAIL {name}");
            for e in &errs {
                println!("       {e}");
            }
            failed += 1;
        }
    }

    println!();
    println!("conformance (rust): {tables} tables, {steps} trace steps, {failed} failed");

    // A fixture with no adapter is skipped, not passed. Phase 4 and 5 start
    // with everything skipped and that has to be visible.
    let declared = std::fs::read_dir(&root)
        .map(|d| {
            d.filter_map(Result::ok)
                .filter(|e| e.path().extension().is_some_and(|x| x == "tbl"))
                .count()
        })
        .unwrap_or(0);
    if declared > tables {
        println!(
            "       {} fixture(s) have no Rust adapter (skipped)",
            declared - tables
        );
    }

    let _ = Expect::Stay; // keep the import honest across refactors
    if failed == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}
