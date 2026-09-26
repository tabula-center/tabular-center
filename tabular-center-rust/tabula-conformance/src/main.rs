//! Runs every fixture in `spec/conformance` against the Rust implementation.

use std::path::PathBuf;
use std::process::ExitCode;

use tabula_conformance::machines::{all, Adapter};
use tabula_conformance::{last_segment, load, Expect, Trace};

fn spec_root() -> PathBuf {
    // The crate lives at tabular-center-rust/tabula-conformance; the spec is repo-relative.
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

/// Write one rendering out, when asked with `--emit=<dir>`.
///
/// Nothing is compared here, and nothing is committed. `.tbl` and `.trace`
/// are the contract; `.grid`, `.mmd`, `.lint` and `.cov` are renderings OF
/// that contract, and every implementation produces its own at check time for
/// `tools/verify renderings-agree` to diff against the others. A committed
/// golden made one implementation's output the expectation for the other two,
/// and had to be re-blessed whenever any of them changed a character.
fn emit(dir: Option<&std::path::Path>, name: &str, ext: &str, got: &str) {
    if let Some(dir) = dir {
        let path = dir.join(format!("{name}.{ext}"));
        if let Err(e) = std::fs::write(&path, got) {
            eprintln!("could not write {}: {e}", path.display());
        }
    }
}

fn main() -> ExitCode {
    // Where to write renderings, if anywhere. No `--bless`: there is nothing
    // committed to bless.
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
        // The diagram. The only output compared ACROSS implementations, and
        // the reason it is worth a golden: they had already drifted on edge
        // ordering before anything looked.
        emit(emit_dir, name, "mmd", &adapter.mermaid());
        // The lints carry the most per-language logic there is -- thresholds,
        // the dead-row/no-static-exit subsumption, the fully-static gate on
        // reachability. Nothing compared them across languages until now, so a
        // rule could drift in one and nobody would know.
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
            // Lints are advisory as OUTPUT -- a rule that is a judgement call
            // must not fail a build. But the output itself is compared against
            // a golden above, because "advisory" is about the user's machine,
            // not about whether three implementations agree.
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

    println!();
    println!("conformance (rust): {tables} tables, {steps} trace steps, {failed} failed");

    // A fixture with no adapter is skipped, not passed -- and each one is NAMED, on
    // its own line starting with `skip `, because that prefix is what `tools/verify`
    // collects into the ledger it prints before the verdict. A count said how many
    // were missing without saying which, and a count is invisible to the ledger, so
    // the one place skips are supposed to be visible was the one place these never
    // appeared.
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
    // `all()` again rather than a binding: the loop above consumes the vec,
    // and `name()` is `&'static str`, so the names outlive the temporary.
    // Building the adapters twice costs nothing and keeps the loop reading as
    // a consuming iteration, which is what it is.
    let covered: Vec<&str> = all().iter().map(|a| a.name()).collect();
    for name in declared.iter().filter(|n| !covered.contains(&n.as_str())) {
        println!("skip {name} (no Rust adapter)");
    }

    let _ = Expect::Stay; // keep the import honest across refactors
    if failed == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}
