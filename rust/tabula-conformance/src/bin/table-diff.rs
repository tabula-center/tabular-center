//! Renders a machine's matrix as a diffable grid, and diffs it against the
//! fixture.
//!
//! A PR that changes machine behaviour should show the *table* diff, not just
//! the code diff. Reviewing a matrix is what this library is for; reviewing a
//! `match` arm is what it exists to avoid.

use std::process::ExitCode;

use tabula_conformance::machines::all;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let want = args.first().map(String::as_str);

    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/conformance");
    let mut any = false;

    for adapter in all() {
        let name = adapter.name();
        if want.is_some_and(|w| w != name) {
            continue;
        }
        any = true;

        match tabula_conformance::load(&root, name) {
            Ok((spec, _)) => {
                println!("{}", spec_grid(&spec));
                let errs = adapter.check_table(&spec);
                if errs.is_empty() {
                    println!("  (matches the generated table)\n");
                } else {
                    println!("  DIFFERS from the generated table:");
                    for e in errs {
                        println!("    {e}");
                    }
                    println!();
                }
            }
            Err(e) => println!("{name}: {e}"),
        }
    }

    if !any {
        eprintln!(
            "no such fixture; known: {:?}",
            all().iter().map(|a| a.name()).collect::<Vec<_>>()
        );
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

/// Column-aligned grid, same shape as `tabula::export::to_grid`.
fn spec_grid(s: &tabula_conformance::Spec) -> String {
    let texts: Vec<Vec<String>> = s
        .cells
        .iter()
        .map(|r| r.iter().map(|c| c.to_string()).collect())
        .collect();

    let label_w = s
        .states
        .iter()
        .map(String::len)
        .chain(std::iter::once(s.machine.len()))
        .max()
        .unwrap_or(0);

    let col_w: Vec<usize> = (0..s.actions.len())
        .map(|j| {
            texts
                .iter()
                .map(|r| r[j].len())
                .chain(std::iter::once(s.actions[j].len()))
                .max()
                .unwrap_or(0)
        })
        .collect();

    let mut out = format!("{:w$}", s.machine, w = label_w);
    for (j, a) in s.actions.iter().enumerate() {
        out.push_str(&format!("  {:w$}", a, w = col_w[j]));
    }
    out.push('\n');
    for (i, st) in s.states.iter().enumerate() {
        out.push_str(&format!("{:w$}", st, w = label_w));
        for (j, t) in texts[i].iter().enumerate() {
            out.push_str(&format!("  {:w$}", t, w = col_w[j]));
        }
        out.push('\n');
    }
    out
}
