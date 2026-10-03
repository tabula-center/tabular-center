//! Runs every fixture in `spec/conformance` against the Rust implementation.

use std::path::PathBuf;
use std::process::ExitCode;

use tabular_center_conformance::machines::{all, Adapter};
use tabular_center_conformance::{last_segment, load, Expect, Trace};

fn spec_root() -> PathBuf {
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

fn emit(dir: Option<&std::path::Path>, name: &str, ext: &str, got: &str) {
    if let Some(dir) = dir {
        let path = dir.join(format!("{name}.{ext}"));
        if let Err(e) = std::fs::write(&path, got) {
            eprintln!("could not write {}: {e}", path.display());
        }
    }
}

fn main() -> ExitCode {
    let emit_dir =
        std::env::args().find_map(|a| a.strip_prefix("--emit=").map(std::path::PathBuf::from));
    if let Some(dir) = &emit_dir {
        if let Err(e) = std::fs::create_dir_all(dir) {
            eprintln!("could not create {}: {e}", dir.display());
            return ExitCode::FAILURE;
        }
    }
    let emit_dir = emit_dir.as_deref();
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
        emit(emit_dir, name, "grid", &adapter.grid());
        emit(emit_dir, name, "mmd", &adapter.mermaid());
        emit(emit_dir, name, "lint", &adapter.lint());
        emit(emit_dir, name, "cov", &adapter.coverage_report());
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
            for line in adapter.lint().lines() {
                println!("       {line}");
            }
        } else {
            println!("FAIL {name}");
            for e in &errs {
                println!("       {e}");
            }
            failed += 1;
        }
    }

    match tabular_center_conformance::step_algebra::replay(&root) {
        Ok((cases, failures)) if failures.is_empty() => {
            println!("ok   step-algebra ({cases} cases)");
        }
        Ok((_, failures)) => {
            println!("FAIL step-algebra");
            for f in &failures {
                println!("       {f}");
            }
            failed += 1;
        }
        Err(e) => {
            println!("FAIL step-algebra: {e}");
            failed += 1;
        }
    }

    println!();
    println!("conformance (rust): {tables} tables, {steps} trace steps, {failed} failed");

    let mut declared: Vec<String> = std::fs::read_dir(&root)
        .map(|d| {
            d.filter_map(Result::ok)
                .filter_map(|e| {
                    let n = e.file_name().to_string_lossy().into_owned();
                    n.strip_suffix(".tbl").map(str::to_string)
                })
                .collect()
        })
        .unwrap_or_default();
    declared.sort();
    let covered: Vec<&str> = all().iter().map(|a| a.name()).collect();
    for name in declared.iter().filter(|n| !covered.contains(&n.as_str())) {
        println!("skip {name} (no Rust adapter)");
    }

    let _ = Expect::Stay;
    if failed == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}
